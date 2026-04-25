#!/bin/bash

set -euo pipefail

# ===============================
# ⚙️ Config
# ===============================

KUMA_URL="http://uptime-kuma:3001"

# Compose project name used in deploy.sh (-p docker-stack)
DOCKER_NETWORK="${DOCKER_NETWORK:-docker-stack_internal}"

command -v docker >/dev/null 2>&1 || { echo "[✗] Docker not found."; exit 1; }

: "${KUMA_USERNAME:?Set KUMA_USERNAME in environment (the admin user you created in the Kuma UI)}"
: "${KUMA_PASSWORD:?Set KUMA_PASSWORD in environment}"

echo ""
echo "===== Uptime Kuma monitor setup: $(date) ====="

# ===============================
# 🔍 Pre-flight checks
# ===============================

if ! docker network ls --format '{{.Name}}' | grep -q "^${DOCKER_NETWORK}$"; then
  echo "[✗] Network '$DOCKER_NETWORK' not found. Is the stack running? Try: docker compose up -d"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^uptime-kuma$'; then
  echo "[✗] Container 'uptime-kuma' is not running. Try: docker compose up -d"
  exit 1
fi

echo "[✓] Stack is up."

# ===============================
# 🐍 Python setup script (Socket.IO API)
# Uptime Kuma has no REST login endpoint — all auth is via Socket.IO.
# uptime-kuma-api handles this transparently.
# ===============================

TMPPY=$(mktemp /tmp/kuma_setup_XXXXXX.py)
trap 'rm -f "$TMPPY"' EXIT

cat > "$TMPPY" << 'PYEOF'
import os, sys
from uptime_kuma_api import UptimeKumaApi, MonitorType

api = UptimeKumaApi(os.environ["KUMA_URL"])

try:
    api.login(os.environ["KUMA_USERNAME"], os.environ["KUMA_PASSWORD"])
    print("[✓] Authenticated.")

    monitors = api.get_monitors()
    existing = {m["name"] for m in monitors}

    def add_http(name, url):
        if name in existing:
            print(f"[=] Skip (exists): {name}")
            return
        r = api.add_monitor(
            type=MonitorType.HTTP,
            name=name,
            url=url,
            interval=60,
            maxretries=3,
        )
        print(f"[✓] Added: {name} (id={r.get('monitorID', '?')})")

    def add_tcp(name, hostname, port):
        if name in existing:
            print(f"[=] Skip (exists): {name}")
            return
        r = api.add_monitor(
            type=MonitorType.PORT,
            name=name,
            hostname=hostname,
            port=port,
            interval=60,
            maxretries=3,
        )
        print(f"[✓] Added: {name} (id={r.get('monitorID', '?')})")

    print("[*] Adding HTTP monitors...")

    # Dashboard / UI services
    add_http("Homepage",          "http://homepage:3000")
    add_http("Grafana",           "http://grafana:3000")
    add_http("Portainer",         "http://portainer:9000")
    add_http("Speedtest Tracker", "http://speedtest-tracker:80")
    add_http("AdGuard",           "http://adguard:80")

    # Home Assistant is on the host network — use the Pi's static IP
    add_http("Home Assistant",    "http://192.168.6.59:8123")

    # Observability stack
    add_http("Prometheus",        "http://prometheus:9090/-/healthy")
    add_http("Node Exporter",     "http://node-exporter:9100/metrics")
    add_http("cAdvisor",          "http://cadvisor:8080")

    # Reverse proxy
    add_http("Caddy",             "http://caddy-proxy:80")

    print("[*] Adding TCP monitors...")

    # Loki uses a distroless image (no shell/wget), so no HTTP health endpoint is available.
    # Port 3100 is the gRPC + HTTP API port; a TCP check confirms the process is listening.
    add_tcp("Loki", "loki", 3100)

    print("[✓] All monitors configured.")

except Exception as e:
    print(f"[✗] Error: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    try:
        api.disconnect()
    except Exception:
        pass
PYEOF

echo "[*] Authenticating and configuring monitors..."

docker run --rm \
  --network "$DOCKER_NETWORK" \
  -v "$TMPPY:/setup.py:ro" \
  -e KUMA_URL="$KUMA_URL" \
  -e KUMA_USERNAME="$KUMA_USERNAME" \
  -e KUMA_PASSWORD="$KUMA_PASSWORD" \
  python:3-slim \
  sh -c "pip install uptime-kuma-api --quiet && python3 /setup.py"

echo "===== Setup complete: $(date) ====="
