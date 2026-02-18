# 🏠 Raspberry Pi Home Lab

A production-inspired home lab running on a Raspberry Pi 4B, built around a full observability stack, smart home integration, network-level ad blocking, and a secure reverse proxy. This project applies real-world DevOps practices — monitoring, log aggregation, alerting, and container management — in a self-hosted home environment.

---

## 🏗️ Architecture

> Architecture diagram coming soon

Traffic flows through **Caddy** (reverse proxy with automatic HTTPS) into an isolated internal Docker network. All services are accessible via `.home` local domains. Metrics are scraped by **Prometheus** from Node Exporter and cAdvisor, visualised in **Grafana**, and alerts are routed through **Alertmanager** to **Telegram**. Logs are collected by **Promtail** and stored in **Loki**, also visualised in Grafana.

---

## 📦 Stack

### 🏠 Core
| Service | Purpose |
|---|---|
| Home Assistant | Smart home automation and control |
| AdGuard Home | Network-wide DNS ad/tracker blocking + DHCP |
| Homepage | Centralised dashboard for all services |

### 📊 Observability
| Service | Purpose |
|---|---|
| Prometheus | Metrics collection and storage |
| Grafana | Dashboards and visualisation |
| Loki | Log aggregation and storage |
| Promtail | Log shipping to Loki |
| Node Exporter | Host-level metrics (CPU, memory, disk) |
| cAdvisor | Per-container resource metrics |
| Alertmanager | Alert routing and Telegram notifications |
| Uptime Kuma | Service uptime monitoring |
| Speedtest Tracker | Internet speed tracking over time |

### 🛠️ Management
| Service | Purpose |
|---|---|
| Portainer | Docker container management UI |
| Watchtower | Automated container image updates |

### 🌐 Networking
| Service | Purpose |
|---|---|
| Caddy | Reverse proxy with automatic HTTPS |

---

## 📸 Screenshots

> Screenshots coming soon — Grafana dashboards, Homepage, Uptime Kuma

---

## ✅ Prerequisites

- Raspberry Pi 4B (64-bit OS)
- Docker + Docker Compose installed
- `.home` domain resolution via AdGuard Home or `/etc/hosts`

---

## 🚀 Setup

### 1. Clone the Repository
```bash
git clone https://github.com/estebanmorenoit/rpi-home-lab.git
cd rpi-home-lab
```

### 2. Configure AdGuard Home (DNS)

Access AdGuard Home at `http://<your-pi-ip>:3000` to complete the onboarding wizard:

- Set DNS ports (default: 53)
- Define upstream DNS servers (e.g., `1.1.1.1`, `8.8.8.8`)
- Set admin credentials
- Configure a `*.home` DNS rewrite pointing to your Pi's IP

### 3. Prepare Home Assistant Config
```bash
cp homeassistant/configuration.yaml.example homeassistant/configuration.yaml
```

This configures Home Assistant to work behind Caddy's reverse proxy:
```yaml
default_config:

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12

frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
```

### 4. Create the `.env` File
```bash
cp .env.example .env
```

Then edit `.env` with your values:
```env
TZ=Europe/London
EMAIL=your-email@example.com
APP_KEY=your-speedtest-app-key
```

### 5. Configure Caddy

Edit `caddy/Caddyfile` to route your `.home` domains:
```caddy
grafana.home {
  reverse_proxy grafana:3000
}

homeassistant.home {
  reverse_proxy homeassistant:8123
}
```

Add a block for each service you want to expose.

### 6. Start the Stack
```bash
docker compose up -d
```

### 7. Verify Services
```bash
docker compose ps
```

All services should show as `healthy` or `running`. Access your dashboard at `http://homepage.home` once DNS is configured.

---

## 🧹 Maintenance

A `maintenance.sh` script handles routine cleanup:

- Removes unused containers, images, volumes, and networks
- Configures log rotation for container logs
- Optionally purges old metric or log data
```bash
chmod +x maintenance.sh
./maintenance.sh
```

### Automate with Cron (weekly, Sundays at 3AM)
```bash
crontab -e
```
```cron
0 3 * * 0 /home/esteban/docker-stack/maintenance.sh >> /home/esteban/docker-stack/maintenance.log 2>&1
```

---

## 📉 Data Retention

| Service | Retention | Config |
|---|---|---|
| Prometheus | 7 days | `--storage.tsdb.retention.time=7d` |
| Loki | Configurable | Set in `loki/local-config.yaml` |

---

## 🗺️ Roadmap

- [ ] Add architecture diagram
- [ ] Add Grafana dashboard screenshots
- [ ] Ansible playbook for Pi provisioning
- [ ] GitHub Actions CI for compose validation

---

## ⚠️ Notes

- Never commit your `.env` file — it's in `.gitignore` by default
- Validate volume paths and permissions before first launch
- Back up your Home Assistant config regularly
