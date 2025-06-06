# Raspberry Pi Docker Home Lab Stack

A lightweight and extensible Docker-based home lab setup for Raspberry Pi. This stack includes system monitoring, network-level DNS/ad blocking, log aggregation, smart home integration, and a reverse proxy with local `.home` domains.

---

## 📦 Stack Components

- **Prometheus** – Metrics collection
- **Grafana** – Visual dashboards
- **Loki** – Log aggregation
- **Promtail** – Log shipping
- **cAdvisor** – Container metrics
- **Node Exporter** – Host metrics
- **Portainer** – Docker management UI
- **AdGuard Home** – DNS-based ad and tracker blocking
- **Home Assistant** – Smart home control
- **Homepage** – Customizable start page/dashboard
- **Caddy** – Local reverse proxy for `.home` domains

---

## ✅ Prerequisites

- Raspberry Pi (64-bit OS)
- Docker + Docker Compose installed
- `.home` domain resolution set up (e.g. via Pi-hole, AdGuard, or /etc/hosts)
- Public IP or static LAN IP for reverse proxy

---

## 🚀 Setup

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/docker-stack.git
cd docker-stack
```

### 2. Edit the Caddyfile

Ensure all services are routed properly:

```caddy
http://grafana.home {
  reverse_proxy grafana:3000
}
```

Add more routes as needed.

### 3. Start the Stack

```bash
docker compose up -d
```

### 4. Optional: Local DNS or Hosts File

Add entries to your DNS server or `/etc/hosts`:

```
192.168.1.100 grafana.home prometheus.home portainer.home ...
```

Replace `192.168.1.100` with your Pi’s IP.

---

## 🧹 Maintenance Script

A `maintenance.sh` script is included to:

- Clean up unused containers, images, volumes, and networks
- Set up logrotate for container logs
- (Optionally) purge metric or log data

### Make it Executable

```bash
chmod +x maintenance.sh
```

### Run it Manually

```bash
./maintenance.sh
```

---

## ⏱️ Automate via Cron

To schedule weekly cleanups (e.g., Sundays at 3AM):

```bash
crontab -e
```

Add this line:

```cron
0 3 * * 0 /home/esteban/docker-stack/maintenance.sh >> /home/esteban/docker-stack/maintenance.log 2>&1
```

Verify:

```bash
crontab -l
```

---

## 📉 Data Retention Suggestions

- **Prometheus**: add flag `--storage.tsdb.retention.time=7d`
- **Loki**: configure retention if using filesystem/S3

---

## Configuration Details

### Example `.env` File

This file holds environment-specific variables. Create it in the root of your project directory:

```env
TZ=Europe/London
```

### Example `docker-compose.yml`

This example shows the core layout, organized into categories:

```yaml
version: "3.9"

services:
  # === Dashboards and UIs ===
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    ...

  grafana:
    image: grafana/grafana:latest
    ...

  portainer:
    image: portainer/portainer-ce:latest
    ...

  # === Monitoring and Logging ===
  prometheus:
    image: prom/prometheus:latest
    ...

  loki:
    image: grafana/loki:latest
    ...

  promtail:
    image: grafana/promtail:latest
    ...

  node-exporter:
    image: prom/node-exporter:latest
    ...

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    ...

  # === DNS and Proxy ===
  adguard:
    image: adguard/adguardhome:latest
    ...

  caddy-proxy:
    image: caddy:latest
    ...

  # === Home Automation ===
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    ...

  # === Container Updates ===
  watchtower:
    image: containrrr/watchtower:latest
    ...
```
---

## Notes

- Ensure all `docker-compose.yml` paths and port mappings suit your network setup.
- Backups are recommended before major changes.