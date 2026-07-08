#!/bin/sh
# =============================================================================
#  obserae demo installer — one-liner bootstrap
# -----------------------------------------------------------------------------
#  Deploy the full obserae demo lab (Docker Compose) in one command:
#
#      curl -fsSL https://demo.obserae.com | sh
#
#  This script is the ONLY file hosted on demo.obserae.com. It fetches the rest
#  of the demo (compose file, Dockerfiles, configs, scripts) from the public
#  GitHub repo, then builds and starts the stack. It also manages the demo's
#  lifecycle (status / logs / update / uninstall).
#
#  POSIX sh on purpose (runs on the host via `| sh`). Pass a command/flags to a
#  piped invocation with `-s --`, e.g.:
#      curl -fsSL https://demo.obserae.com | sh -s -- --with-ldap
#      curl -fsSL https://demo.obserae.com | sh -s -- uninstall --yes
# =============================================================================
set -eu

# --- Configuration (override via environment) --------------------------------
REPO_OWNER="${REPO_OWNER:-spartan-conseil}"
REPO_NAME="${REPO_NAME:-obserae}"
REPO_REF="${REPO_REF:-main}"                 # branch or tag; also --ref
DEMO_SUBDIR="${DEMO_SUBDIR:-obserae-demo}"   # path of the demo inside the repo
DEMO_DIR="${OBSERAE_DEMO_DIR:-./obserae-demo}"
UI_URL="${UI_URL:-http://127.0.0.1:8081}"
INSTALL_URL="${INSTALL_URL:-https://demo.obserae.com}"

# --- Runtime state -----------------------------------------------------------
CMD=""
EXTRA_ARGS=""
WITH_LDAP="${WITH_LDAP:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
NO_START=0
DOCKER_SUDO=""
DOWNLOADER=""
_tmpfiles=""

# --- Logging -----------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="$(printf '\033[0m')"; C_INFO="$(printf '\033[1;34m')"
  C_WARN="$(printf '\033[1;33m')"; C_ERR="$(printf '\033[1;31m')"
  C_OK="$(printf '\033[1;32m')"; C_DIM="$(printf '\033[2m')"
else
  C_RESET=''; C_INFO=''; C_WARN=''; C_ERR=''; C_OK=''; C_DIM=''
fi
info() { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2; }
ok()   { printf '%s==>%s %s\n' "$C_OK"   "$C_RESET" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err()  { printf '%serror:%s %s\n'   "$C_ERR"  "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

cleanup() { [ -n "$_tmpfiles" ] && rm -f $_tmpfiles 2>/dev/null || true; }
trap cleanup EXIT INT TERM

have()    { command -v "$1" >/dev/null 2>&1; }
new_tmp() { REPLY="$(mktemp)"; _tmpfiles="$_tmpfiles $REPLY"; }   # -> $REPLY

usage() {
  cat >&2 <<EOF
obserae demo installer

Usage (remote):
  curl -fsSL $INSTALL_URL | sh
  curl -fsSL $INSTALL_URL | sh -s -- [command] [options]

Commands:
  install      Fetch files, build images and start the stack (default)
  status       Show container status and UI health
  logs [svc]   Follow logs (optionally for a single service, e.g. sensor)
  update       Re-fetch files, rebuild and restart (pulls newer images)
  uninstall    Stop the stack, delete its volumes and the demo directory
  help         Show this help

Options:
  --with-ldap  Also provision FreeIPA + LDAP demo users (slow first boot)
  --dir PATH   Install/target directory (default: ./obserae-demo)
  --ref REF    Git branch or tag to fetch from (default: main)
  --yes, -y    Assume "yes" for confirmations (non-interactive uninstall)
  --no-start   install: fetch and validate the compose file only, don't build/up

Environment overrides:
  OBSERAE_DEMO_DIR, REPO_OWNER, REPO_NAME, REPO_REF, DEMO_SUBDIR,
  OBSERAE_IMAGE, ACTIVITY_MIN_SLEEP, ACTIVITY_MAX_SLEEP
EOF
}

# --- Argument parsing --------------------------------------------------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      install|status|logs|update|uninstall)
        if [ -z "$CMD" ]; then CMD="$1"; else EXTRA_ARGS="$EXTRA_ARGS $1"; fi ;;
      help|-h|--help) CMD="help" ;;
      --with-ldap)    WITH_LDAP=1 ;;
      --yes|-y)       ASSUME_YES=1 ;;
      --no-start)     NO_START=1 ;;
      --dir)          shift; [ $# -gt 0 ] || die "--dir needs a path"; DEMO_DIR="$1" ;;
      --dir=*)        DEMO_DIR="${1#--dir=}" ;;
      --ref)          shift; [ $# -gt 0 ] || die "--ref needs a value"; REPO_REF="$1" ;;
      --ref=*)        REPO_REF="${1#--ref=}" ;;
      --)             ;;   # ignore separator
      -*)             die "unknown option: $1 (try 'help')" ;;
      *)              EXTRA_ARGS="$EXTRA_ARGS $1" ;;   # e.g. a service name for logs
    esac
    shift
  done
  [ -n "$CMD" ] || CMD="install"
  # RAW_BASE can be overridden directly (e.g. for testing against a local mirror);
  # otherwise it is the GitHub raw base for the configured repo/ref/subdir.
  RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$REPO_REF/$DEMO_SUBDIR}"
}

# --- Downloader (curl or wget) -----------------------------------------------
detect_downloader() {
  if have curl; then DOWNLOADER="curl"
  elif have wget; then DOWNLOADER="wget"
  else DOWNLOADER=""; fi
}
# fetch <url> -> stdout (fails on HTTP error)
fetch() {
  if [ "$DOWNLOADER" = "curl" ]; then curl -fsSL "$1"
  else wget -qO- "$1"; fi
}
# ui_up: connection-level health check (any HTTP response = up), soft
ui_up() {
  if [ "$DOWNLOADER" = "curl" ]; then curl -sS -o /dev/null --max-time 3 "$UI_URL" 2>/dev/null
  elif [ "$DOWNLOADER" = "wget" ]; then wget -q -O /dev/null --timeout=3 "$UI_URL" 2>/dev/null
  else return 1; fi
}

# --- Docker preflight --------------------------------------------------------
detect_compose() {
  have docker || die "Docker is not installed — see https://docs.docker.com/engine/install/"
  if docker compose version >/dev/null 2>&1; then
    DOCKER_SUDO=""
  elif have sudo && sudo docker compose version >/dev/null 2>&1; then
    DOCKER_SUDO="sudo"
    warn "You can't reach Docker directly; using sudo. (Add yourself to the 'docker' group to avoid this.)"
  else
    die "Docker Compose v2 is required (the 'docker compose' subcommand), reachable directly or via sudo."
  fi
}
require_daemon() {
  $DOCKER_SUDO docker info >/dev/null 2>&1 || die "Cannot reach the Docker daemon — is it running?"
}
# compose ... : run docker compose inside the demo dir (picks up its .env)
compose() { ( cd "$DEMO_DIR" && exec $DOCKER_SUDO docker compose "$@" ); }

check_host() {
  [ "$(uname -s)" = "Linux" ] || warn "Non-Linux host ($(uname -s)): the softflowd sensor uses network_mode:host and won't capture the bridges the same way on Docker Desktop (README §8)."
  if have ss; then
    if ss -ltnH 2>/dev/null | grep -qE '(127\.0\.0\.1|0\.0\.0\.0|\*|\[::\]|\[::1\]):8081([^0-9]|$)'; then
      warn "TCP port 8081 on localhost looks busy — the obserae UI may fail to bind ($UI_URL)."
    fi
  fi
}

require_demo_dir() {
  [ -f "$DEMO_DIR/docker-compose.yml" ] || die "no demo found at '$DEMO_DIR' (run 'install' first, or pass --dir)."
}

# --- .env management (persist chosen options for later compose commands) ------
set_env_kv() {   # file key value  — upsert KEY=VALUE
  _f="$1"; _k="$2"; _v="$3"
  new_tmp
  [ -f "$_f" ] && grep -v "^${_k}=" "$_f" > "$REPLY" 2>/dev/null || true
  printf '%s=%s\n' "$_k" "$_v" >> "$REPLY"
  mv "$REPLY" "$_f"
}
del_env_kv() {   # file key  — remove KEY= line if present
  _f="$1"; _k="$2"
  [ -f "$_f" ] || return 0
  new_tmp
  grep -v "^${_k}=" "$_f" > "$REPLY" 2>/dev/null || true
  mv "$REPLY" "$_f"
}
write_env() {
  _env="$DEMO_DIR/.env"
  # COMPOSE_PROFILES=ldap makes `docker compose up` include the FreeIPA service
  # (which is behind the "ldap" profile). Written here so every later compose
  # command in this dir is consistent without needing the flag again.
  if [ "$WITH_LDAP" = "1" ]; then set_env_kv "$_env" COMPOSE_PROFILES ldap
  else del_env_kv "$_env" COMPOSE_PROFILES; fi
  [ -n "${OBSERAE_IMAGE:-}" ]       && set_env_kv "$_env" OBSERAE_IMAGE       "$OBSERAE_IMAGE"       || true
  [ -n "${ACTIVITY_MIN_SLEEP:-}" ]  && set_env_kv "$_env" ACTIVITY_MIN_SLEEP  "$ACTIVITY_MIN_SLEEP"  || true
  [ -n "${ACTIVITY_MAX_SLEEP:-}" ]  && set_env_kv "$_env" ACTIVITY_MAX_SLEEP  "$ACTIVITY_MAX_SLEEP"  || true
}

# --- Fetch demo files from GitHub via the manifest ---------------------------
fetch_files() {
  [ -n "$DOWNLOADER" ] || die "need curl or wget to download the demo files"
  have mktemp || die "mktemp is required"
  info "Fetching demo files from $RAW_BASE"
  mkdir -p "$DEMO_DIR"
  new_tmp; _manifest="$REPLY"
  fetch "$RAW_BASE/manifest.txt" > "$_manifest" \
    || die "cannot download manifest.txt — check that $REPO_OWNER/$REPO_NAME@$REPO_REF is public and $DEMO_SUBDIR exists"
  [ -s "$_manifest" ] || die "manifest.txt is empty"
  _count=0
  while IFS= read -r rel || [ -n "$rel" ]; do
    rel="$(printf '%s' "$rel" | tr -d '\r')"
    case "$rel" in
      ""|\#*)   continue ;;               # blank / comment
      /*|*..*)  die "unsafe manifest entry: $rel" ;;
    esac
    dest="$DEMO_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    printf '%s  %s%s\n' "$C_DIM" "$rel" "$C_RESET" >&2
    fetch "$RAW_BASE/$rel" > "$dest" || die "failed to download $rel"
    case "$rel" in *.sh) chmod +x "$dest" ;; esac
    _count=$((_count + 1))
  done < "$_manifest"
  [ "$_count" -gt 0 ] || die "manifest listed no files"
  ok "Fetched $_count files into $DEMO_DIR"
}

# When run privileged via sudo, hand the demo dir back to the human who invoked
# it so the manual import commands (host-side `< file` redirects) and later edits
# work without root. No-op when not root or when there is no invoking user.
fix_ownership() {
  [ "$(id -u)" -eq 0 ] || return 0
  [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] || return 0
  _owner="$SUDO_USER"
  [ -n "${SUDO_GID:-}" ] && _owner="$SUDO_USER:$SUDO_GID"
  chown -R "$_owner" "$DEMO_DIR" 2>/dev/null \
    || warn "could not chown $DEMO_DIR to $SUDO_USER — you may need sudo to read the import files."
}

# --- Confirmations (works under `curl | sh` via /dev/tty) --------------------
confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  if [ -r /dev/tty ]; then
    printf '%s [y/N] ' "$1" > /dev/tty
    read -r _ans < /dev/tty || _ans=""
    case "$_ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
  fi
  warn "no TTY for confirmation — pass --yes to proceed non-interactively"
  return 1
}

wait_ui() {
  info "Waiting for the obserae UI at $UI_URL ..."
  _i=0
  while [ "$_i" -lt 30 ]; do
    if ui_up; then ok "obserae UI is up: $UI_URL"; return 0; fi
    _i=$((_i + 1)); sleep 2
  done
  warn "obserae UI not reachable yet — it may still be starting. Follow it with:  curl -fsSL $INSTALL_URL | sh -s -- logs obserae"
}

print_next_steps() {
  _sudo=""; [ -n "$DOCKER_SUDO" ] && _sudo="sudo "
  cat <<EOF

${C_OK}obserae demo is up.${C_RESET}

  UI:     $UI_URL
  Login:  admin / admin   (demo credentials — rotate before exposing the UI)

Give it 2–5 minutes for the NetFlow v9 templates to arrive, then flows fill in.

Load the ready-made configuration (cartography, flow matrix, rules) — master key FIRST:
  cd "$DEMO_DIR"
  SOCK=/var/lib/obserae/run/obserae.sock
  ${_sudo}docker compose exec -T obserae obserae-cli --socket "\$SOCK" masterkey import - < obserae-masterkey.txt
  ${_sudo}docker compose exec -T obserae obserae-cli --socket "\$SOCK" config import  - < obserae-config.yaml

Manage the demo (from this same directory):
  curl -fsSL $INSTALL_URL | sh -s -- status
  curl -fsSL $INSTALL_URL | sh -s -- logs sensor
  curl -fsSL $INSTALL_URL | sh -s -- uninstall --yes
EOF
  if [ "$WITH_LDAP" != "1" ]; then
    cat <<EOF

To also demo LDAP sign-in (FreeIPA — slow first boot), re-run with --with-ldap:
  curl -fsSL $INSTALL_URL | sh -s -- --with-ldap
EOF
  fi
}

# --- Commands ----------------------------------------------------------------
cmd_install() {
  detect_downloader
  detect_compose
  check_host
  fetch_files
  write_env
  fix_ownership
  if [ "$NO_START" = "1" ]; then
    info "Validating the compose file (--no-start) ..."
    compose config -q && ok "Compose file is valid. Skipping build/up (--no-start)."
    return 0
  fi
  require_daemon
  info "Building images (first run pulls the base images) ..."
  compose build
  info "Starting the stack ..."
  compose up -d
  wait_ui
  if [ "$WITH_LDAP" = "1" ]; then
    info "Provisioning FreeIPA + LDAP (first boot can take several minutes) ..."
    ( cd "$DEMO_DIR" && $DOCKER_SUDO ./scripts/setup-ldap.sh ) \
      || warn "setup-ldap.sh did not complete — re-run it later (README §5): (cd $DEMO_DIR && ${DOCKER_SUDO:+sudo }./scripts/setup-ldap.sh)"
  fi
  print_next_steps
}

cmd_update() {
  require_demo_dir
  detect_downloader
  detect_compose
  require_daemon
  fetch_files
  write_env
  fix_ownership
  info "Rebuilding and restarting (pulling newer images) ..."
  compose up -d --build --pull always
  wait_ui
  ok "Update complete."
}

cmd_status() {
  require_demo_dir
  detect_downloader
  detect_compose
  require_daemon
  compose ps
  if ui_up; then ok "UI reachable: $UI_URL"; else warn "UI not responding: $UI_URL"; fi
  compose logs --tail 1 sensor 2>/dev/null || true
}

cmd_logs() {
  require_demo_dir
  detect_compose
  require_daemon
  # EXTRA_ARGS may name a single service (e.g. sensor); unquoted on purpose.
  # shellcheck disable=SC2086
  compose logs -f --tail 100 $EXTRA_ARGS
}

cmd_uninstall() {
  require_demo_dir
  detect_compose
  require_daemon
  case "$DEMO_DIR" in
    ""|/|.|./|"$HOME"|"$HOME/") die "refusing to remove unsafe path: '$DEMO_DIR'" ;;
  esac
  confirm "This STOPS the demo and DELETES its data volumes and the directory '$DEMO_DIR'. Continue?" || { info "Aborted."; exit 0; }
  info "Stopping the stack and removing volumes ..."
  compose down -v --remove-orphans || warn "compose down reported an error; continuing with directory removal."
  rm -rf "$DEMO_DIR"
  ok "Demo removed ('$DEMO_DIR' deleted, volumes dropped)."
}

# --- Main --------------------------------------------------------------------
main() {
  parse_args "$@"
  case "$CMD" in
    install)   cmd_install ;;
    update)    cmd_update ;;
    status)    cmd_status ;;
    logs)      cmd_logs ;;
    uninstall) cmd_uninstall ;;
    help)      usage ;;
    *)         usage; exit 1 ;;
  esac
}

main "$@"
