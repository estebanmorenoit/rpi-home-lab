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
# 🐍 Python setup script (raw Socket.IO)
# Uptime Kuma has no REST login endpoint — auth and monitor creation are
# Socket.IO-only. We use python-socketio directly so we control the full
# payload (including the `conditions` field required by Kuma v2).
# ===============================

TMPPY=$(mktemp /tmp/kuma_setup_XXXXXX.py)
trap 'rm -f "$TMPPY"' EXIT

cat > "$TMPPY" << 'PYEOF'
import os, sys, threading
import socketio

KUMA_URL = os.environ["KUMA_URL"]
USERNAME  = os.environ["KUMA_USERNAME"]
PASSWORD  = os.environ["KUMA_PASSWORD"]

sio = socketio.Client(logger=False, engineio_logger=False)

existing = set()
_monitor_list_ready = threading.Event()

@sio.on("monitorList")
def _on_monitor_list(data):
    for m in (data.values() if isinstance(data, dict) else []):
        if isinstance(m, dict) and m.get("name"):
            existing.add(m["name"])
    _monitor_list_ready.set()

sio.connect(KUMA_URL)

def _call(event, data=None):
    resp = [None]
    done = threading.Event()
    def cb(r):
        resp[0] = r
        done.set()
    sio.emit(event, data or {}, callback=cb)
    if not done.wait(15):
        raise TimeoutError(f"No response for '{event}'")
    return resp[0]

try:
    r = _call("login", {"username": USERNAME, "password": PASSWORD, "token": ""})
    if not r or not r.get("ok"):
        print(f"[✗] Auth failed: {r.get('msg', r) if r else 'no response'}", file=sys.stderr)
        sys.exit(1)
    print("[✓] Authenticated.")

    _monitor_list_ready.wait(5)  # Kuma pushes monitorList after login

    def add_monitor(**data):
        name = data["name"]
        if name in existing:
            print(f"[=] Skip (exists): {name}")
            return
        r = _call("add", data)
        if r and r.get("ok"):
            print(f"[✓] Added: {name} (id={r.get('monitorID', '?')})")
        else:
            msg = r.get("msg", str(r)) if r else "no response"
            print(f"[✗] Failed to add {name}: {msg}", file=sys.stderr)

    HTTP = dict(method="GET", interval=60, maxretries=3, timeout=30,
                accepted_statuscodes=["200-299"], conditions=[], notificationIDList={})
    TCP  = dict(interval=60, maxretries=3, timeout=30,
                accepted_statuscodes=["200-299"], conditions=[], notificationIDList={})

    print("[*] Adding HTTP monitors...")

    # Dashboard / UI services
    add_monitor(type="http", name="Homepage",          url="http://homepage:3000",              **HTTP)
    add_monitor(type="http", name="Grafana",           url="http://grafana:3000",               **HTTP)
    add_monitor(type="http", name="Portainer",         url="http://portainer:9000",             **HTTP)
    add_monitor(type="http", name="Speedtest Tracker", url="http://speedtest-tracker:80",       **HTTP)
    add_monitor(type="http", name="AdGuard",           url="http://adguard:80",                 **HTTP)

    # Home Assistant is on the host network — use the Pi's static IP
    add_monitor(type="http", name="Home Assistant",    url="http://192.168.6.59:8123",          **HTTP)

    # Observability stack
    add_monitor(type="http", name="Prometheus",        url="http://prometheus:9090/-/healthy",  **HTTP)
    add_monitor(type="http", name="Node Exporter",     url="http://node-exporter:9100/metrics", **HTTP)
    add_monitor(type="http", name="cAdvisor",          url="http://cadvisor:8080",              **HTTP)

    # Reverse proxy
    add_monitor(type="http", name="Caddy",             url="http://caddy-proxy:80",             **HTTP)

    # External sites
    add_monitor(type="http", name="Esteban Moreno - Portfolio", url="https://estebanmoreno.link/", **HTTP)

    print("[*] Adding TCP monitors...")

    # Loki uses a distroless image (no shell/wget), so no HTTP health endpoint is available.
    # Port 3100 is the gRPC + HTTP API port; a TCP check confirms the process is listening.
    add_monitor(type="port", name="Loki", hostname="loki", port=3100, **TCP)

    print("[✓] All monitors configured.")

except Exception as e:
    print(f"[✗] Error: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    try:
        sio.disconnect()
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
  sh -c "pip install 'python-socketio[client]' --quiet && python3 /setup.py"

echo "===== Setup complete: $(date) ====="
