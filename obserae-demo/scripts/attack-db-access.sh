#!/usr/bin/env bash
# =============================================================================
#  attack-db-access.sh -- simulate direct workstation -> database access
# -----------------------------------------------------------------------------
#  Opt-in demo attack. Makes a workstation connect DIRECTLY to the PostgreSQL
#  databases (10.0.20.30 prod / 10.0.30.30 preprod), bypassing the app tier --
#  an east-west segmentation violation. obserae should flag it because the flow
#  matrix only allows backends (not workstations) to reach the databases.
#
#  Usage:  ./scripts/attack-db-access.sh [count] [ws-service]
#            count       how many connections to make  (default 5)
#            ws-service  workstation to run it from     (default ws1, the "dev" role)
#
#  See it in obserae with, e.g.:
#    FROM sessions | WHERE src_addr == "workstations" AND dst_addr == "databases"
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (where docker-compose.yml lives)

COUNT="${1:-5}"
WS="${2:-ws1}"
HOSTS=("10.0.20.30" "10.0.30.30")   # db-prod / db-preprod

# Docker must be reachable. In this lab that usually means running with sudo;
# fail loudly here instead of hanging silently later.
if ! docker version >/dev/null 2>&1; then
  echo "ERROR: cannot reach the Docker daemon. Run this script with the same" >&2
  echo "       privileges you use for docker, e.g.  sudo $0" >&2
  exit 1
fi

echo "==> Direct DB access from ${WS}, ${COUNT} connection(s)..."
for i in $(seq 1 "${COUNT}"); do
  h="${HOSTS[$(( i % ${#HOSTS[@]} ))]}"
  echo "    connect ${i}/${COUNT} -> ${h}:5432"
  docker compose exec -T -e PGCONNECT_TIMEOUT=3 "${WS}" \
    psql "postgresql://app:app@${h}:5432/appdb" -c "SELECT 1;" \
    >/dev/null 2>&1 || true
  sleep 2
done

cat <<EOF

Done. ${WS} talked straight to the databases (east-west violation). In obserae:
  - Detection / Flow Matrix: workstation -> databases TCP/5432 (not allowed).
  - NFQL:
      FROM sessions | WHERE src_addr == "workstations" AND dst_addr == "databases"
EOF
