#!/usr/bin/env bash
# =============================================================================
#  obserae lab flow sensor
# -----------------------------------------------------------------------------
#  This container runs with "network_mode: host" and therefore sees the Docker
#  bridge interfaces (obs-dmz, obs-prod, obs-preprod, obs-work). softflowd acts
#  as a passive probe (the equivalent of a SPAN / TAP port on a switch): it
#  observes ALL traffic crossing each bridge, builds bidirectional flows and
#  exports them to obserae.
#
#  It plays the role of a NetFlow exporter (router, firewall, vSwitch).
#
#  IMPORTANT: obserae ingests NetFlow v5/v9 only, on UDP 2055 (no IPFIX). The
#  sensor therefore exports NetFlow v9 to port 2055 by default.
# =============================================================================
set -u

OBSERAE="${OBSERAE_TARGET:-10.0.0.10}"          # obserae IP (mgmt network)
PORT="${OBSERAE_PORT:-2055}"                    # 2055 = NetFlow ingest port
VERSION="${FLOW_VERSION:-9}"                     # 9 = NetFlow v9 (obserae supports v5/v9)
IFACES="${CAPTURE_IFACES:-obs-dmz obs-prod obs-preprod obs-work}"
MAXLIFE="${FLOW_MAXLIFE:-60}"                    # periodic export (keeps the demo lively)

echo "[sensor] export target : ${OBSERAE}:${PORT} (NetFlow v${VERSION})"
echo "[sensor] interfaces     : ${IFACES}"

# Wait for the Docker bridges to exist (they are created with the networks).
for i in $(seq 1 60); do
  missing=0
  for ifn in ${IFACES}; do
    ip link show "${ifn}" >/dev/null 2>&1 || missing=1
  done
  [ "${missing}" -eq 0 ] && break
  echo "[sensor] waiting for bridge interfaces... (${i})"
  sleep 2
done

declare -A PIDS

start_probe() {
  local ifn="$1"
  softflowd \
    -d \
    -i "${ifn}" \
    -v "${VERSION}" \
    -n "${OBSERAE}:${PORT}" \
    -t maxlife="${MAXLIFE}" \
    -t general="${MAXLIFE}" &
  PIDS["${ifn}"]=$!
  echo "[sensor] softflowd started on ${ifn} (pid ${PIDS[$ifn]})"
}

for ifn in ${IFACES}; do
  if ip link show "${ifn}" >/dev/null 2>&1; then
    start_probe "${ifn}"
  else
    echo "[sensor] WARNING: interface ${ifn} missing, skipped."
  fi
done

# Simple supervisor: restart a probe if it dies.
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; exit 0' TERM INT
while true; do
  sleep 5
  for ifn in "${!PIDS[@]}"; do
    if ! kill -0 "${PIDS[$ifn]}" 2>/dev/null; then
      echo "[sensor] softflowd on ${ifn} stopped, restarting."
      start_probe "${ifn}"
    fi
  done
done
