#!/usr/bin/env bash
# =============================================================================
#  User activity simulator (Linux workstation)
# -----------------------------------------------------------------------------
#  Each workstation loops continuously and generates a realistic traffic mix.
#  The internal DNS (DMZ) is used for EVERY name resolution (see "dns:" in the
#  compose file), so each web access first produces a work -> dmz (53) flow.
#
#  Behaviour is weighted by role (ROLE variable):
#    - "healthy" traffic : web browsing (internet), prod/preprod app access
#    - "drift" traffic   : rare deviations (direct DB access, scan, external
#                          beacon) -> these are what make obserae shine in a demo.
# =============================================================================
set -u

ROLE="${ROLE:-generic}"
MIN_SLEEP="${ACTIVITY_MIN_SLEEP:-4}"
MAX_SLEEP="${ACTIVITY_MAX_SLEEP:-12}"

# "Legitimate" public sites (browsing).
PUBLIC_SITES=(
  "https://example.com"
  "https://www.wikipedia.org"
  "https://www.debian.org"
  "https://ftp.gnu.org"
  "https://www.kernel.org"
)

# Domains that are merely resolved (simulate browsing name resolution).
PUBLIC_LOOKUPS=(
  google.com github.com cloudflare.com microsoft.com apple.com
  cdn.jsdelivr.net fonts.googleapis.com api.stripe.com
)

# Internal applications (prod / preprod).
APPS=(
  "https://caddy-prod.corp.lan"
  "https://www.corp.lan"
  "https://caddy-preprod.corp.lan"
  "https://staging.corp.lan"
)

# "Suspicious" external destinations -- DOCUMENTATION ranges (RFC 5737), which
# are not routable on the internet: the SYN creates a flow to investigate in
# obserae without actually reaching anything.
SUSPICIOUS=("203.0.113.66" "198.51.100.13" "192.0.2.200")

log() { echo "[$(date +%H:%M:%S)][${ROLE}] $*"; }

rnd() { echo $((RANDOM % $1)); }

nap() {
  local span=$(( MAX_SLEEP - MIN_SLEEP ))
  [ "${span}" -le 0 ] && span=1
  sleep $(( MIN_SLEEP + (RANDOM % span) ))
}

# ---- "Healthy" actions ------------------------------------------------------

browse_internet() {
  local site="${PUBLIC_SITES[$(rnd ${#PUBLIC_SITES[@]})]}"
  log "web -> ${site}"
  curl -s -k --max-time 5 -o /dev/null "${site}" || true
}

dns_lookup() {
  local d="${PUBLIC_LOOKUPS[$(rnd ${#PUBLIC_LOOKUPS[@]})]}"
  log "dns  -> ${d}"
  dig +timeout=2 +tries=1 "${d}" A >/dev/null 2>&1 || true
}

hit_app() {
  local app="${APPS[$(rnd ${#APPS[@]})]}"
  log "app  -> ${app}"
  curl -s -k --max-time 5 -o /dev/null "${app}" || true
}

# ---- "Drift" actions (rare, probability-triggered) --------------------------

# Direct workstation -> PostgreSQL access (east-west segmentation violation).
direct_db() {
  local hosts=("10.0.20.30" "10.0.30.30")
  local h="${hosts[$(rnd ${#hosts[@]})]}"
  log "DRIFT: direct DB access ${h}:5432"
  PGCONNECT_TIMEOUT=3 psql "postgresql://app:app@${h}:5432/appdb" \
    -c "SELECT 1;" >/dev/null 2>&1 || true
}

# Beacon to a "known-bad" external IP.
beacon() {
  local ip="${SUSPICIOUS[$(rnd ${#SUSPICIOUS[@]})]}"
  log "DRIFT: external beacon ${ip}"
  curl -s --max-time 3 -o /dev/null "http://${ip}/" || true
}

# Internal port scan (reconnaissance).
port_scan() {
  local target="10.0.20.0/28"
  log "DRIFT: scan ${target}"
  nmap -sT -Pn --max-retries 1 --host-timeout 8s -p 22,80,443,5432,8000 \
    "${target}" >/dev/null 2>&1 || true
}

log "starting simulator (min=${MIN_SLEEP}s max=${MAX_SLEEP}s)"

while true; do
  roll=$(rnd 100)

  case "${ROLE}" in
    dev)
      # Developer: lots of app + internet; occasionally hits the DB directly.
      if   [ "${roll}" -lt 45 ]; then hit_app
      elif [ "${roll}" -lt 70 ]; then browse_internet
      elif [ "${roll}" -lt 90 ]; then dns_lookup
      elif [ "${roll}" -lt 96 ]; then direct_db        # drift ~6%
      else                            beacon           # drift ~4%
      fi
      ;;
    ops)
      # Ops: occasionally scans the network (reconnaissance drift).
      if   [ "${roll}" -lt 40 ]; then hit_app
      elif [ "${roll}" -lt 65 ]; then dns_lookup
      elif [ "${roll}" -lt 88 ]; then browse_internet
      else                            port_scan        # drift ~12%
      fi
      ;;
    finance|hr)
      # Office profiles: mostly web + a little app; rare beacon.
      if   [ "${roll}" -lt 55 ]; then browse_internet
      elif [ "${roll}" -lt 80 ]; then dns_lookup
      elif [ "${roll}" -lt 97 ]; then hit_app
      else                            beacon           # drift ~3%
      fi
      ;;
    *)
      # Balanced generic profile.
      if   [ "${roll}" -lt 40 ]; then browse_internet
      elif [ "${roll}" -lt 70 ]; then dns_lookup
      else                            hit_app
      fi
      ;;
  esac

  nap
done
