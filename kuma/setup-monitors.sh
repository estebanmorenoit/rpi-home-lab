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

KUMA_URL          = os.environ["KUMA_URL"]
USERNAME          = os.environ["KUMA_USERNAME"]
PASSWORD          = os.environ["KUMA_PASSWORD"]
STATUS_PAGE_SLUG  = os.environ.get("KUMA_STATUS_PAGE_SLUG",  "default")
STATUS_PAGE_TITLE = os.environ.get("KUMA_STATUS_PAGE_TITLE", "Home Lab Status")

sio = socketio.Client(logger=False, engineio_logger=False)

existing = {}  # name -> monitor_id
_monitor_list_ready = threading.Event()

@sio.on("monitorList")
def _on_monitor_list(data):
    for k, m in (data.items() if isinstance(data, dict) else []):
        if isinstance(m, dict) and m.get("name"):
            existing[m["name"]] = int(k)
    _monitor_list_ready.set()

sio.connect(KUMA_URL)

def _call(event, data=None):
    resp = [None]
    done = threading.Event()
    def cb(r):
        resp[0] = r
        done.set()
    # Tuples are unpacked as multiple Socket.IO arguments by python-socketio
    sio.emit(event, data if data is not None else {}, callback=cb)
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
            return existing[name]
        r = _call("add", data)
        if r and r.get("ok"):
            mid = r.get("monitorID")
            print(f"[✓] Added: {name} (id={mid})")
            existing[name] = mid
            return mid
        else:
            msg = r.get("msg", str(r)) if r else "no response"
            print(f"[✗] Failed to add {name}: {msg}", file=sys.stderr)
            return None

    HTTP = dict(method="GET", interval=60, maxretries=3, timeout=30,
                accepted_statuscodes=["200-299"], conditions=[], notificationIDList={})
    TCP  = dict(interval=60, maxretries=3, timeout=30,
                accepted_statuscodes=["200-299"], conditions=[], notificationIDList={})

    print("[*] Adding HTTP monitors...")
    monitor_ids = []

    # Dashboard / UI services
    monitor_ids.append(add_monitor(type="http", name="Homepage",          url="http://homepage:3000",              **HTTP))
    monitor_ids.append(add_monitor(type="http", name="Grafana",           url="http://grafana:3000",               **HTTP))
    monitor_ids.append(add_monitor(type="http", name="Portainer",         url="http://portainer:9000",             **HTTP))
    monitor_ids.append(add_monitor(type="http", name="Speedtest Tracker", url="http://speedtest-tracker:80",       **HTTP))
    monitor_ids.append(add_monitor(type="http", name="AdGuard",           url="http://adguard:80",                 **HTTP))

    # Home Assistant is on the host network — use the Pi's static IP
    monitor_ids.append(add_monitor(type="http", name="Home Assistant",    url="http://192.168.6.59:8123",          **HTTP))

    # Observability stack
    monitor_ids.append(add_monitor(type="http", name="Prometheus",        url="http://prometheus:9090/-/healthy",  **HTTP))
    monitor_ids.append(add_monitor(type="http", name="Node Exporter",     url="http://node-exporter:9100/metrics", **HTTP))
    monitor_ids.append(add_monitor(type="http", name="cAdvisor",          url="http://cadvisor:8080",              **HTTP))

    # Reverse proxy
    monitor_ids.append(add_monitor(type="http", name="Caddy",             url="http://caddy-proxy:80",             **HTTP))

    # External sites
    monitor_ids.append(add_monitor(type="http", name="Esteban Moreno - Portfolio", url="https://estebanmoreno.link/", **HTTP))

    print("[*] Adding TCP monitors...")

    # Loki uses a distroless image (no shell/wget), so no HTTP health endpoint is available.
    # Port 3100 is the gRPC + HTTP API port; a TCP check confirms the process is listening.
    monitor_ids.append(add_monitor(type="port", name="Loki", hostname="loki", port=3100, **TCP))

    print("[✓] All monitors configured.")

    # ── Status page ────────────────────────────────────────────────────────────
    # Upsert a status page so the Homepage widget can see all monitors via slug.
    valid_ids = [mid for mid in monitor_ids if mid is not None]
    print(f"\n[*] Syncing status page '{STATUS_PAGE_SLUG}'...")

    page_resp = _call("getStatusPage", STATUS_PAGE_SLUG)
    if page_resp and page_resp.get("ok"):
        config = page_resp.get("config", {})
        print(f"[=] Status page exists (id={config.get('id', '?')})")
    else:
        r = _call("addStatusPage", [STATUS_PAGE_TITLE, STATUS_PAGE_SLUG])
        if not r or not r.get("ok"):
            msg = r.get("msg", str(r)) if r else "no response"
            print(f"[✗] Failed to create status page: {msg}", file=sys.stderr)
            sys.exit(1)
        print(f"[✓] Created status page '{STATUS_PAGE_SLUG}'")
        page_resp = _call("getStatusPage", STATUS_PAGE_SLUG)
        config = page_resp.get("config", {}) if page_resp else {}

    public_group_list = [{"name": "Services", "weight": 0,
                          "monitorList": [{"id": mid} for mid in valid_ids]}]
    # Kuma v2 saveStatusPage takes (slug, config, imgDataUrl, publicGroupList)
    # Pass as tuple — python-socketio unpacks tuples as separate Socket.IO args
    r = _call("saveStatusPage", (STATUS_PAGE_SLUG, config, "", public_group_list))
    if r and r.get("ok"):
        print(f"[✓] Status page '{STATUS_PAGE_SLUG}' updated with {len(valid_ids)} monitors.")
    else:
        msg = r.get("msg", str(r)) if r else "no response"
        print(f"[✗] Failed to save status page: {msg}", file=sys.stderr)

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
  -e KUMA_STATUS_PAGE_SLUG="${KUMA_STATUS_PAGE_SLUG:-default}" \
  -e KUMA_STATUS_PAGE_TITLE="${KUMA_STATUS_PAGE_TITLE:-Home Lab Status}" \
  python:3-slim \
  sh -c "pip install 'python-socketio[client]' --quiet && python3 /setup.py"

echo "===== Setup complete: $(date) ====="
