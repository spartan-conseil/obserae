#!/usr/bin/env bash
# =============================================================================
#  attack-beacon.sh -- simulate a beacon to "known-bad" external IPs
# -----------------------------------------------------------------------------
#  Opt-in demo attack. Makes a workstation repeatedly call out to hard-coded
#  "suspicious" external IPs. Those are RFC 5737 DOCUMENTATION ranges
#  (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24), which are not routable on
#  the internet: the SYN creates a flow to investigate in obserae without
#  actually reaching anything.
#
#  Usage:  ./scripts/attack-beacon.sh [count] [ws-service]
#            count       how many beacons to send   (default 5)
#            ws-service  workstation to run it from  (default ws4, the "hr" role)
#
#  See it in obserae with, e.g.:
#    FROM sessions | WHERE dst_addr == "203.0.113.0/24"
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (where docker-compose.yml lives)

COUNT="${1:-5}"
WS="${2:-ws4}"
SUSPICIOUS=("203.0.113.66" "198.51.100.13" "192.0.2.200")

# Docker must be reachable. In this lab that usually means running with sudo;
# fail loudly here instead of hanging silently later.
if ! docker version >/dev/null 2>&1; then
  echo "ERROR: cannot reach the Docker daemon. Run this script with the same" >&2
  echo "       privileges you use for docker, e.g.  sudo $0" >&2
  exit 1
fi

echo "==> Beaconing to known-bad IPs from ${WS}, ${COUNT} time(s)..."
for i in $(seq 1 "${COUNT}"); do
  ip="${SUSPICIOUS[$(( i % ${#SUSPICIOUS[@]} ))]}"
  echo "    beacon ${i}/${COUNT} -> ${ip}"
  docker compose exec -T "${WS}" \
    curl -s --max-time 3 -o /dev/null "http://${ip}/" || true
  sleep 2
done

cat <<EOF

Done. ${WS} just beaconed to simulated known-bad destinations. Look in obserae:
  - Detection: workstation -> known-bad external ranges.
  - NFQL:
      FROM sessions | WHERE dst_addr == "203.0.113.0/24"
EOF
