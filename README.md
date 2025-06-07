
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
- `.home` domain resolution set up (e.g. via Pi-hole, AdGuard, or `/etc/hosts`)
- Public IP or static LAN IP for reverse proxy

---

## 🚀 Setup

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/docker-stack.git
cd docker-stack
```

### 2. Prepare Home Assistant Config

Copy the example configuration to enable proxy access on new setups:

```bash
cp homeassistant/configuration.yaml.example homeassistant/configuration.yaml
```

This ensures Home Assistant is configured to work behind a reverse proxy like Caddy.

### 3. Edit the Caddyfile

Ensure all services are routed properly:

```caddy
http://grafana.home {
  reverse_proxy grafana:3000
}
```

Add routes for all required services.

### 4. Start the Stack

```bash
docker compose up -d
```

### 5. Optional: Local DNS or Hosts File

Add entries to your DNS server or `/etc/hosts`:

```
192.168.1.100 grafana.home prometheus.home portainer.home homeassistant.home ...
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

- **Prometheus**: use `--storage.tsdb.retention.time=7d`
- **Loki**: configure chunk retention if using file/S3 storage

---

## Configuration Details

### Example `.env` File

This file holds environment-specific variables. Create it in the root of your project directory:

```env
TZ=Europe/London
EMAIL=your-email@example.com
```

### Home Assistant Configuration

The file `homeassistant/configuration.yaml.example` includes a basic setup with trusted proxies:

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

lovelace:
  mode: "storage"
  resources:
    - url: "/hacsfiles/button-card/button-card.js"
      type: "module"
    # Add other resources here...
```

Copy this file to `homeassistant/configuration.yaml` and modify as needed.

---

## Notes

- Validate paths, volumes, and permissions for your specific Pi or network.
- Backups are recommended before major changes.
- For new setups, ensure configuration templates are copied before launching containers.
