#!/usr/bin/env bash
# =============================================================================
#  User activity simulator (Linux workstation)
# -----------------------------------------------------------------------------
#  Each workstation loops continuously and generates a realistic, BENIGN traffic
#  mix only: web browsing, internal DNS resolution and prod/preprod app access.
#  The internal DNS (DMZ) is used for EVERY name resolution (see "dns:" in the
#  compose file), so each web access first produces a work -> dmz (53) flow.
#
#  Behaviour is weighted by role (ROLE variable) purely to vary the mix; no
#  workstation deviates on its own. Malicious/"drift" scenarios (network scan,
#  direct DB access, external beacon) are NO LONGER generated here: they are
#  opt-in and triggered on demand, one at a time, via scripts/attack-*.sh so you
#  can build a clean baseline first and then observe exactly what one attack
#  produces in obserae.
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

log "starting simulator (min=${MIN_SLEEP}s max=${MAX_SLEEP}s)"

# Every branch is benign. The role only shifts the weighting so the traffic mix
# looks a bit different per workstation. Attacks are triggered on demand via
# scripts/attack-*.sh, never from this loop.
while true; do
  roll=$(rnd 100)

  case "${ROLE}" in
    dev)
      # Developer: lots of app + internet.
      if   [ "${roll}" -lt 45 ]; then hit_app
      elif [ "${roll}" -lt 75 ]; then browse_internet
      else                            dns_lookup
      fi
      ;;
    ops)
      # Ops: balanced app / dns / web.
      if   [ "${roll}" -lt 40 ]; then hit_app
      elif [ "${roll}" -lt 65 ]; then dns_lookup
      else                            browse_internet
      fi
      ;;
    finance|hr)
      # Office profiles: mostly web + a little app.
      if   [ "${roll}" -lt 55 ]; then browse_internet
      elif [ "${roll}" -lt 80 ]; then dns_lookup
      else                            hit_app
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
