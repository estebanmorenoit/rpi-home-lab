# Building a Production-Grade Self-Hosted Home Lab on a Raspberry Pi

Running your own home lab used to mean expensive hardware, complex networking, and hours of manual configuration. This project changes that. With a single Raspberry Pi, Docker Compose, and a few hundred lines of config, you can have a fully self-hosted infrastructure stack that rivals what you'd find in a small business — complete with full-stack observability, network-wide ad blocking, smart home automation, and a secure reverse proxy.

In this post, I'll walk you through the architecture, the key design decisions, and how to get the entire stack running from scratch.

---

## What We're Building

This stack turns a Raspberry Pi into a self-hosted home lab with the following capabilities:

- **Network-wide DNS ad/tracker blocking** via AdGuard Home
- **Smart home automation** via Home Assistant
- **Full-stack observability** — metrics, logs, and dashboards via Prometheus, Grafana, Loki, and Promtail
- **Reverse proxy with `.home` domains** via Caddy
- **Service uptime monitoring** via Uptime Kuma
- **ISP bandwidth tracking** via Speedtest Tracker
- **Automated dependency updates** via Renovate
- **Automated CI/CD deployment** via GitHub Actions + Tailscale

Every service is containerised, health-checked, and wired together as code. No click-ops. No manual reconfiguration after a reboot.

---

## Architecture

Before diving into setup, it's worth understanding how traffic flows through the stack:

```
Browser / Device
      │
      ▼
AdGuard Home (DNS · *.home → Pi LAN IP)
      │
      ▼
Caddy (reverse proxy · :80 :443)
      │
      ├─→ Grafana
      ├─→ Prometheus
      ├─→ AdGuard Home UI
      ├─→ Uptime Kuma
      ├─→ Speedtest Tracker
      ├─→ Homepage
      ├─→ Portainer
      └─→ Home Assistant (host network · LAN IP)
```

**Traffic flow:**

1. Client devices point to **AdGuard Home** as their DNS server. A wildcard rewrite resolves all `*.home` domains to the Pi's LAN IP.
2. **Caddy** receives every HTTP request and reverse-proxies it to the correct container based on the `Host` header.
3. **Home Assistant** runs on the host network (required for device and mDNS discovery) and is proxied via its LAN IP rather than a container name.
4. Everything else lives on an isolated `internal` Docker network. Only Caddy bridges `internal` and `frontend` — no service is directly reachable from outside the host.

---

## The Stack

| Service | Role |
|---|---|
| Caddy | Reverse proxy for all `.home` domains |
| AdGuard Home | DNS ad/tracker blocking + DNS rewrites |
| Home Assistant | Smart home automation platform |
| Prometheus | Metrics collection and storage |
| Grafana | Code-provisioned dashboards |
| Loki | Log aggregation |
| Promtail | Log shipping from host and containers |
| Node Exporter | Host-level metrics (CPU, memory, disk, network) |
| cAdvisor | Per-container resource metrics |
| Uptime Kuma | Service uptime monitoring with alerting |
| Speedtest Tracker | Scheduled ISP bandwidth monitoring |
| Homepage | Unified dashboard for all services |
| Portainer | Docker management UI |
| Tailscale | Secure remote access to services from anywhere |

---

## Key Design Decisions

A few non-obvious choices worth explaining before you deploy:

**Network isolation** — Two Docker networks are defined. All services join `internal`. Only Caddy also joins `frontend`. This means nothing is directly reachable from outside the host except through the reverse proxy.

**Health checks and startup ordering** — Caddy depends on Grafana, Prometheus, AdGuard, and Loki all being `healthy` before it starts. Grafana waits for Prometheus and Loki. Promtail waits for Loki. This prevents a cascade of 502s on cold starts — a common pain point with naive Docker Compose setups.

**AdGuard and Docker's internal DNS** — AdGuard binds to port 53 on the host, which can disrupt Docker's embedded DNS resolver (`127.0.0.11`) via iptables. Caddy is explicitly configured with `dns: 127.0.0.11` to pin it to Docker's resolver and prevent it falling back to AdGuard for container name lookups.

**Grafana provisioned from code** — Dashboards and data sources are mounted from `./grafana/provisioning` and `./grafana/dashboards` as read-only volumes. No manual configuration required after deployment.

---

## Prerequisites

- Raspberry Pi running 64-bit OS
- Docker + Docker Compose V2 installed
- Git

---

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/estebanmorenoit/docker-stack.git
cd docker-stack
```

### 2. Configure Your Environment

```bash
cp .env.example .env
```

Open `.env` and fill in your values:

```env
TZ=Europe/London
EMAIL=your@email.com
APP_KEY=                      # generate: openssl rand -base64 32

ADGUARD_IP=192.168.x.x        # your Pi's LAN IP
HOMEPAGE_ALLOWED_HOSTS=your.domain.com
```

### 3. Configure Home Assistant for the Reverse Proxy

```bash
cp homeassistant/configuration.yaml.example homeassistant/configuration.yaml
```

This enables `use_x_forwarded_for` and trusts the Docker subnet (`172.16.0.0/12`) so Home Assistant correctly identifies client IPs when sitting behind Caddy.

### 4. Review the Caddyfile

All `.home` routes are already defined in `caddy/Caddyfile`. Update hostnames if needed:

```caddy
http://grafana.home {
    reverse_proxy grafana:3000
}

homeassistant.home {
    reverse_proxy homeassistant:8123
}
```

### 5. Start the Stack

```bash
docker compose up -d
```

Verify everything came up healthy:

```bash
docker compose ps
```

### 6. Configure AdGuard DNS Rewrite

Access AdGuard at `http://<pi-ip>:8080`. Go to **Filters → DNS rewrites** and add:

| Domain | Answer |
|---|---|
| `*.home` | `<your-pi-ip>` |

Then point your router to the Pi as its DNS server. All devices on your network will now resolve `.home` domains automatically.

**Remote access via Tailscale** — If you run Tailscale on the Pi, you can also add a `*.tail` rewrite pointing to the Pi's Tailscale IP. This lets you reach all your `.home` services from any device on your tailnet, even when you're away from home.

---

## Deployment

The `deploy.sh` script reconciles the running stack with the latest commit in a single command:

```bash
./deploy.sh
```

Under the hood it runs: `git pull` → `docker compose pull` → `docker compose up -d --remove-orphans`

This is a GitOps-style workflow — the repository is the source of truth, and the script brings the running state in line with it.

---

## CI/CD Pipeline

The stack includes a GitHub Actions workflow that automatically deploys to the Pi on every push to `main`. It connects to the Pi securely over Tailscale — no open ports, no exposed SSH, no VPN configuration required.

```
GitHub push → GitHub Actions runner
                    │
                    ▼
            Connect to Tailscale (ephemeral node tagged: github-deployer)
                    │
                    ▼
            SSH into Pi over Tailscale
                    │
                    ▼
            git pull → docker compose pull → docker compose up -d
```

### Prerequisites

**1. Tailscale OAuth credentials**

Create an OAuth client in the Tailscale admin console with `all` scopes. Add as GitHub repository secrets:
- `TS_OAUTH_CLIENT_ID`
- `TS_OAUTH_SECRET`

**2. Register the ACL tag**

In the Tailscale admin console under Access Controls, add the tag to `tagOwners`:

```json
"tagOwners": {
    "tag:github-deployer": ["autogroup:admin"],
},
```

This allows the ephemeral GitHub Actions node to join your tailnet.

**3. SSH deploy key**

Generate a dedicated key on the Pi and add the public key to `authorized_keys`:

```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_deploy -N ""
cat ~/.ssh/github_deploy.pub >> ~/.ssh/authorized_keys
```

Add the private key contents as a GitHub repository secret named `SSH_PRIVATE_KEY`.

Also trust GitHub's SSH host key on the Pi, and switch the repo remote to SSH:

```bash
ssh-keyscan github.com >> ~/.ssh/known_hosts
git remote set-url origin git@github.com:<your-username>/<your-repo>.git
```

### The workflow

```yaml
name: Deploy with Tailscale GitHub Action

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Connect to Tailscale
        uses: tailscale/github-action@v3
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:github-deployer

      - name: Setup SSH agent
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: SSH into Raspberry Pi over Tailscale
        run: |
          ssh -o StrictHostKeyChecking=accept-new user@raspberrypi.<your-tailnet>.ts.net <<'EOF'
            cd ~/docker-stack
            git pull origin main
            docker compose pull
            docker compose up -d --remove-orphans
          EOF
```

Once configured, every push to `main` automatically updates the running stack — no manual SSH required.

---

## Observability

Once the stack is running, your full observability pipeline looks like this:

| What | How |
|---|---|
| Host metrics | Node Exporter → Prometheus → Grafana |
| Container metrics | cAdvisor → Prometheus → Grafana |
| Container & system logs | Promtail → Loki → Grafana |
| Service uptime | Uptime Kuma |
| ISP bandwidth | Speedtest Tracker (every hour) |

Prometheus retains 7 days of metrics — appropriate for a resource-constrained Pi. Grafana dashboards are provisioned from code, so no manual setup is required after first boot.

---

## Maintenance

`maintenance.sh` handles routine housekeeping — pruning unused Docker images, containers, volumes, and networks, cleaning Loki log chunks older than 7 days, and rotating Docker container logs.

Schedule it weekly via cron:

```cron
0 3 * * 0 /path/to/docker-stack/maintenance.sh >> /path/to/docker-stack/maintenance.log 2>&1
```

---

## Automated Dependency Updates

[Renovate](https://docs.renovatebot.com/) is configured to automatically open pull requests when new image versions are published. No manual tracking of upstream releases required — the dependency dashboard gives you a full view of what's pinned, what's outdated, and what PRs are open.

---

## Wrapping Up

This stack demonstrates that a Raspberry Pi is more than capable of running a production-grade self-hosted infrastructure. The combination of Docker Compose, a GitOps deploy workflow, automated CI/CD over Tailscale, code-provisioned dashboards, and automated dependency updates means you get consistency, reproducibility, and maintainability — the same properties you'd expect from a professional environment.

The full source is available on [GitHub](https://github.com/estebanmorenoit/docker-stack). Clone it, adapt it to your setup, and feel free to raise issues or PRs.

---

*Have questions or want to share how you've extended the stack? Leave a comment below.*
