#!/bin/bash

set -euo pipefail

# ===============================
# 🕒 Timestamp Start
# ===============================
echo ""
echo "===== Maintenance started: $(date) ====="

# ===============================
# 🔍 Pre-checks
# ===============================
command -v docker >/dev/null 2>&1 || { echo "[✗] Docker not found. Exiting."; exit 1; }
command -v logrotate >/dev/null 2>&1 || { echo "[✗] logrotate not found. Exiting."; exit 1; }

# ===============================
# 🧼 Docker Cleanup
# ===============================
echo "[*] Cleaning up unused Docker images, containers, networks, and volumes..."
docker system prune -af --volumes

# ===============================
# 📉 Loki Log Retention (7 days)
# ===============================
LOKI_CHUNKS_DIR="/home/esteban/docker-stack/loki/chunks"  # Use absolute path for cron
if [ -d "$LOKI_CHUNKS_DIR" ]; then
  echo "[*] Cleaning up Loki log chunks older than 7 days..."
  find "$LOKI_CHUNKS_DIR" -type f -mtime +7 -delete
else
  echo "[!] Loki chunks directory not found: $LOKI_CHUNKS_DIR"
fi

# ===============================
# 🗑️ Docker Log Rotation Setup
# ===============================
LOGROTATE_CONF="/etc/logrotate.d/docker-containers"

if [ ! -f "$LOGROTATE_CONF" ]; then
  echo "[*] Setting up logrotate for Docker container logs..."
  sudo tee "$LOGROTATE_CONF" > /dev/null <<EOF
/var/lib/docker/containers/*/*.log {
  rotate 7
  daily
  compress
  missingok
  delaycompress
  copytruncate
  notifempty
}
EOF
else
  echo "[*] Logrotate config already exists at $LOGROTATE_CONF"
fi

echo "[*] Running logrotate manually for Docker logs..."
sudo logrotate -f "$LOGROTATE_CONF"

# ===============================
# 🧾 Optional: Rotate this script's log output
# ===============================
MAINTENANCE_LOG="/home/esteban/docker-stack/maintenance.log"
MAINTENANCE_ROTATE_CONF="/etc/logrotate.d/docker-maintenance-log"

if [ ! -f "$MAINTENANCE_ROTATE_CONF" ]; then
  echo "[*] Setting up logrotate for maintenance log..."
  sudo tee "$MAINTENANCE_ROTATE_CONF" > /dev/null <<EOF
$MAINTENANCE_LOG {
  weekly
  rotate 4
  compress
  missingok
  notifempty
  copytruncate
}
EOF
fi

# ===============================
# ✅ Done
# ===============================
echo "[✓] Maintenance complete!"
echo "===== Maintenance finished: $(date) ====="
