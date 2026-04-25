#!/bin/bash

set -euo pipefail

# ===============================
# ⚙️ Config
# ===============================

KUMA_URL="http://uptime-kuma:3001"

# Compose project name used in deploy.sh (-p docker-stack)
DOCKER_NETWORK="${DOCKER_NETWORK:-docker-stack_internal}"

command -v docker  >/dev/null 2>&1 || { echo "[✗] Docker not found."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "[✗] python3 not found."; exit 1; }

: "${KUMA_USERNAME:?Set KUMA_USERNAME in environment (the admin user you created in the Kuma UI)}"
: "${KUMA_PASSWORD:?Set KUMA_PASSWORD in environment}"

echo ""
echo "===== Uptime Kuma monitor setup: $(date) ====="

# ===============================
# 🌐 Helpers
# ===============================

# Run curl inside the Docker internal network so we can reach uptime-kuma:3001 directly.
kuma_curl() {
  docker run --rm --network "$DOCKER_NETWORK" curlimages/curl:latest \
    --silent "$@"
}

# ===============================
# 🔑 Auth
# ===============================

echo "[*] Authenticating..."

LOGIN_PAYLOAD=$(python3 -c "
import json, os
print(json.dumps({
    'username': os.environ['KUMA_USERNAME'],
    'password': os.environ['KUMA_PASSWORD']
}))
")

LOGIN_RESP=$(kuma_curl \
  -X POST "$KUMA_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  --data-raw "$LOGIN_PAYLOAD")

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('token', ''))
")

if [ -z "$TOKEN" ]; then
  echo "[✗] Auth failed. Response: $LOGIN_RESP"
  exit 1
fi
echo "[✓] Authenticated."

# ===============================
# 📋 Fetch existing monitor names (idempotency)
# ===============================

EXISTING=$(kuma_curl \
  -H "Authorization: Bearer $TOKEN" \
  "$KUMA_URL/api/monitor" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
monitors = data.values() if isinstance(data, dict) else data
print('\n'.join(m.get('name', '') for m in monitors if isinstance(m, dict)))
")

exists() {
  echo "$EXISTING" | grep -qxF "$1"
}

# ===============================
# ➕ Add functions
# ===============================

add_http() {
  local name="$1" url="$2"

  if exists "$name"; then
    echo "[=] Skip (exists): $name"
    return
  fi

  PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'type': 'http',
    'name': sys.argv[1],
    'url': sys.argv[2],
    'method': 'GET',
    'interval': 60,
    'maxretries': 3,
    'timeout': 30,
    'accepted_statuscodes': ['200-299'],
    'active': True
}))
" "$name" "$url")

  RESP=$(kuma_curl \
    -X POST "$KUMA_URL/api/monitor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    --data-raw "$PAYLOAD")

  ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','?'))" 2>/dev/null || echo "?")
  echo "[✓] Added: $name (id=$ID)"
}

add_tcp() {
  local name="$1" host="$2" port="$3"

  if exists "$name"; then
    echo "[=] Skip (exists): $name"
    return
  fi

  PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'type': 'port',
    'name': sys.argv[1],
    'hostname': sys.argv[2],
    'port': int(sys.argv[3]),
    'interval': 60,
    'maxretries': 3,
    'timeout': 30,
    'active': True
}))
" "$name" "$host" "$port")

  RESP=$(kuma_curl \
    -X POST "$KUMA_URL/api/monitor" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    --data-raw "$PAYLOAD")

  ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','?'))" 2>/dev/null || echo "?")
  echo "[✓] Added: $name (id=$ID)"
}

# ===============================
# 📡 HTTP Monitors
# ===============================

echo "[*] Adding HTTP monitors..."

# Dashboard / UI services
add_http "Homepage"          "http://homepage:3000"
add_http "Grafana"           "http://grafana:3000"
add_http "Portainer"         "http://portainer:9000"
add_http "Speedtest Tracker" "http://speedtest-tracker:80"
add_http "AdGuard"           "http://adguard:80"

# Home Assistant is on the host network — use the Pi's static IP
add_http "Home Assistant"    "http://192.168.6.59:8123"

# Observability stack
add_http "Prometheus"        "http://prometheus:9090/-/healthy"
add_http "Node Exporter"     "http://node-exporter:9100/metrics"
add_http "cAdvisor"          "http://cadvisor:8080"

# Reverse proxy
add_http "Caddy"             "http://caddy-proxy:80"

# ===============================
# 🔌 TCP Monitors
# ===============================

echo "[*] Adding TCP monitors..."

# Loki uses a distroless image (no shell/wget), so no HTTP health endpoint is available.
# Port 3100 is the gRPC + HTTP API port; a TCP check confirms the process is listening.
add_tcp "Loki" "loki" 3100

# ===============================
# ✅ Done
# ===============================

echo "[✓] All monitors configured."
echo "===== Setup complete: $(date) ====="
