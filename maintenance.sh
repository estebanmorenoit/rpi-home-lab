#!/bin/bash

# ===============================
# 🧼 Docker Cleanup
# ===============================

echo "[*] Cleaning up unused Docker images, containers, networks, and volumes..."
docker system prune -af --volumes

# ===============================
# 📉 Loki Log Retention (7 days)
# ===============================

LOKI_CHUNKS_DIR="./loki/chunks"  # Adjust if needed
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
# ✅ Done
# ===============================

echo "[✓] Maintenance complete!"
