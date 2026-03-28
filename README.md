# Raspberry Pi Home Lab — Docker Stack

> A production-grade self-hosted infrastructure stack running on a Raspberry Pi. Covers full-stack observability, network-level ad blocking, smart home automation, and a secure reverse proxy — all defined as code and automatically kept up to date.

![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry_Pi-64--bit-A22846?logo=raspberrypi&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-monitoring-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-dashboards-F46800?logo=grafana&logoColor=white)
![Caddy](https://img.shields.io/badge/Caddy-reverse_proxy-00ADD8?logo=caddy&logoColor=white)
![Renovate](https://img.shields.io/badge/Renovate-dependency_updates-1A1F6C?logo=renovatebot&logoColor=white)

---

## Overview

This project turns a Raspberry Pi into a fully self-hosted home lab. Every service is containerised, versioned, and wired together using Docker Compose with explicit health checks and startup dependencies. A GitOps-style deploy script keeps the stack in sync with the repository.

**Skills demonstrated:** Docker & Docker Compose, infrastructure as code, full-stack observability (metrics + logs + dashboards), DNS and reverse proxy configuration, network security design, Linux automation, and automated dependency management.

---

## Architecture

```mermaid
graph TB
    Browser["Browser / Device"]

    subgraph frontend["Docker · frontend network"]
        Caddy["Caddy · :80 :443"]
    end

    subgraph internal["Docker · internal network"]
        AG["AdGuard Home · DNS :53"]
        GF["Grafana"]
        PR["Prometheus"]
        LK["Loki"]
        PT["Promtail"]
        NE["Node Exporter"]
        CA["cAdvisor"]
        UK["Uptime Kuma"]
        ST["Speedtest Tracker"]
        HP["Homepage"]
        PO["Portainer"]
    end

    HA["Home Assistant · host network"]

    Browser -->|"DNS · *.home"| AG
    AG -->|"Pi LAN IP"| Browser
    Browser -->|"HTTP :80"| Caddy
    Caddy --> AG & GF & UK & ST & HP & PO
    Caddy -->|"LAN IP :8123"| HA
    PR --> NE & CA
    GF --> PR & LK
    PT --> LK
```

**Traffic flow:**
1. Client devices point to **AdGuard Home** as their DNS server. A wildcard rewrite resolves all `*.home` domains to the Pi's LAN IP.
2. **Caddy** receives every HTTP request and reverse-proxies it to the correct container based on the `Host` header.
3. **Home Assistant** runs on the host network (required for device/mDNS discovery) and is proxied via its LAN IP rather than a container name.
4. Everything else lives on the isolated `internal` Docker network. Only Caddy bridges `internal` and `frontend`, so no service is directly reachable from outside the host.

---

## Stack

| Service | Role | Version |
|---|---|---|
| [Caddy](https://caddyserver.com/) | Reverse proxy for all `.home` domains | `2.10.0` |
| [AdGuard Home](https://adguard.com/en/adguard-home/overview.html) | Network-wide DNS ad/tracker blocking + DNS rewrites | `v0.107.63` |
| [Home Assistant](https://www.home-assistant.io/) | Smart home automation platform | `2025.6` |
| [Prometheus](https://prometheus.io/) | Metrics collection and storage (7-day retention) | `v3.4.2` |
| [Grafana](https://grafana.com/) | Dashboards provisioned from code | `12.0.2` |
| [Loki](https://grafana.com/oss/loki/) | Log aggregation | `3.5.1` |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Log shipping from host and containers | `3.5.1` |
| [Node Exporter](https://github.com/prometheus/node_exporter) | Host-level metrics (CPU, memory, disk, network) | `v1.9.1` |
| [cAdvisor](https://github.com/google/cadvisor) | Per-container resource metrics | `v0.52.1` |
| [Uptime Kuma](https://uptime.kuma.pet/) | Service uptime monitoring with alerting | `1.23.16` |
| [Speedtest Tracker](https://docs.speedtest-tracker.dev/) | Scheduled ISP bandwidth monitoring | `1.6.1` |
| [Homepage](https://gethomepage.dev/) | Unified dashboard for all services | `v1.3.2` |
| [Portainer](https://www.portainer.io/) | Docker management UI | `2.31.2` |

---

## Design Decisions

**Network isolation** — Two Docker networks are defined. All services join `internal`. Only Caddy also joins `frontend`. This means no service is directly reachable from outside the host except through the reverse proxy.

**Health checks and startup ordering** — Caddy depends on Grafana, Prometheus, AdGuard, and Loki all being `healthy` before it starts. Grafana waits for Prometheus and Loki. Promtail waits for Loki. This prevents a cascade of 502s during cold starts.

**AdGuard DNS and Docker's internal DNS** — AdGuard binds to port 53 on the host, which can disrupt Docker's embedded DNS resolver (`127.0.0.11`) via iptables. Caddy is explicitly configured with `dns: 127.0.0.11` to pin it to Docker's resolver and avoid falling back to AdGuard for container name lookups.

**Grafana provisioned from code** — Dashboards and data sources are mounted from `./grafana/provisioning` and `./grafana/dashboards` as read-only volumes. No manual click-ops required after deployment.

**Automated dependency updates** — [Renovate](https://docs.renovatebot.com/) is configured with a dependency dashboard to automatically open PRs when new image versions are published.

**GitOps-style deployment** — `deploy.sh` pulls the latest commit, pulls updated images, and reconciles the running stack in a single command. Designed to be triggered by a CI runner or run manually.

---

## Repository Structure

```
docker-stack/
├── docker-compose.yaml       # Full stack definition
├── deploy.sh                 # Pull → update → reconcile
├── maintenance.sh            # Docker prune + log rotation
├── renovate.json             # Automated image version updates
├── .env                      # Local secrets (gitignored)
├── .env.example              # Secrets template
├── caddy/
│   └── Caddyfile             # Reverse proxy routes
├── prometheus/
│   └── prometheus.yml        # Scrape targets
├── grafana/
│   ├── provisioning/         # Auto-provisioned data sources
│   └── dashboards/           # Dashboard JSON definitions
├── loki/
│   └── local-config.yaml
├── promtail/
│   └── promtail.yaml
└── homeassistant/
    └── configuration.yaml.example
```

---

## Prerequisites

- Raspberry Pi running 64-bit OS
- Docker + Docker Compose V2 installed
- Git

---

## Setup

### 1. Clone

```bash
git clone https://github.com/estebanmorenoit/docker-stack.git
cd docker-stack
```

### 2. Configure environment

Copy the example and fill in your values:

```bash
cp .env.example .env
```

```env
TZ=Europe/London
EMAIL=your@email.com
APP_KEY=                      # generate: openssl rand -base64 32

ADGUARD_IP=192.168.x.x        # your Pi's LAN IP
HOMEPAGE_ALLOWED_HOSTS=your.domain.com

WATCHTOWER_NOTIFICATION_URL=  # optional: shoutrrr-format notification URL
GITHUB_RUNNER_TOKEN=          # optional: for self-hosted GitHub Actions runner
```

### 3. Configure Home Assistant for reverse proxy

```bash
cp homeassistant/configuration.yaml.example homeassistant/configuration.yaml
```

This enables `use_x_forwarded_for` and trusts the Docker subnet (`172.16.0.0/12`) so Home Assistant correctly identifies client IPs when sitting behind Caddy.

### 4. Configure AdGuard DNS rewrite

Start the stack (step 6), then access AdGuard at `http://<pi-ip>:8080`.

Go to **Filters → DNS rewrites** and add:

| Domain | Answer |
|---|---|
| `*.home` | `<your-pi-ip>` |

Set your router to use the Pi as its DNS server so all devices on the network resolve `.home` domains automatically.

### 5. Review the Caddyfile

All `.home` routes are already defined in `caddy/Caddyfile`. Update hostnames if needed:

```caddy
http://grafana.home {
    reverse_proxy grafana:3000
}

homeassistant.home {
  reverse_proxy homeassistant:8123
}
```

### 6. Start the stack

```bash
docker compose up -d
```

Check everything came up healthy:

```bash
docker compose ps
```

### 7. (Optional) `/etc/hosts` fallback

If not using AdGuard as your DNS, add entries on each client machine:

```
192.168.x.x  grafana.home prometheus.home adguard.home homeassistant.home
192.168.x.x  portainer.home uptimekuma.home speedtest.home homepage.home
```

---

## Deployment

The `deploy.sh` script reconciles the running stack with the latest commit:

```bash
./deploy.sh
```

It runs: `git pull` → `docker compose pull` → `docker compose up -d --remove-orphans`

---

## CI/CD Pipeline

A GitHub Actions workflow automatically deploys to the Pi on every push to `main`, connecting over Tailscale with no open ports required.

**Required GitHub repository secrets:**

| Secret | Description |
|---|---|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
| `SSH_PRIVATE_KEY` | Private key for SSH access to the Pi |

**Setup steps:**

1. Create a Tailscale OAuth client with `all` scopes at login.tailscale.com/admin/settings/oauth
2. Add `tag:github-deployer` to `tagOwners` in your Tailscale ACL policy
3. Generate a deploy key on the Pi and add the public key to `~/.ssh/authorized_keys`:
```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_deploy -N ""
cat ~/.ssh/github_deploy.pub >> ~/.ssh/authorized_keys
ssh-keyscan github.com >> ~/.ssh/known_hosts
git remote set-url origin git@github.com:<your-username>/<your-repo>.git
```
4. Add the private key (`~/.ssh/github_deploy`) as the `SSH_PRIVATE_KEY` secret in GitHub
5. Update the SSH hostname in `.github/workflows/deploy.yaml` to your Pi's Tailscale address

---

## Maintenance

`maintenance.sh` handles routine housekeeping:

- Prunes unused Docker images, containers, volumes, and networks
- Cleans Loki log chunks older than 7 days
- Sets up and runs `logrotate` for Docker container logs

```bash
chmod +x maintenance.sh
./maintenance.sh
```

**Schedule weekly via cron:**

```bash
crontab -e
```

```cron
0 3 * * 0 /path/to/docker-stack/maintenance.sh >> /path/to/docker-stack/maintenance.log 2>&1
```

---

## Observability

| What | How |
|---|---|
| Host metrics | Node Exporter → Prometheus → Grafana |
| Container metrics | cAdvisor → Prometheus → Grafana |
| Container & system logs | Promtail → Loki → Grafana |
| Service uptime | Uptime Kuma |
| ISP bandwidth | Speedtest Tracker (scheduled, every hour) |

Prometheus retains 7 days of metrics — appropriate for a resource-constrained Pi. Grafana dashboards are provisioned from code; no manual setup required after first boot.

---

## Data Retention

| Service | Retention |
|---|---|
| Prometheus | 7 days (`--storage.tsdb.retention.time=7d`) |
| Loki | 7 days (chunks pruned by `maintenance.sh`) |
| Docker logs | 7 daily rotations, compressed |
