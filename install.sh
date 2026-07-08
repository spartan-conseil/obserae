#!/bin/sh
# =============================================================================
#  obserae installer — one-liner bootstrap (production systemd deployment)
# -----------------------------------------------------------------------------
#  Install obserae (daemon + admin CLI) from the latest signed GitHub release:
#
#      curl -fsSL https://get.obserae.com | sudo sh
#
#  It picks the right architecture (amd64/arm64), verifies the SHA256 checksum,
#  verifies the Sigstore keyless signature if `cosign` is available (and tells you
#  what to install if it is not), then deploys the systemd service (user,
#  directories, /etc/obserae/obserae.yaml, unit) as documented in
#  obserae.com/docs/operations. Re-run to upgrade; `uninstall` to remove.
#
#  POSIX sh on purpose (runs on the host via `| sh`). Pass a command/flags to a
#  piped invocation with `-s --`, e.g.:
#      curl -fsSL https://get.obserae.com | sudo sh -s -- --version v0.27.0
#      curl -fsSL https://get.obserae.com | sudo sh -s -- uninstall --purge
# =============================================================================
set -eu

# --- Configuration (override via environment) --------------------------------
REPO_OWNER="${REPO_OWNER:-spartan-conseil}"
REPO_NAME="${REPO_NAME:-obserae}"
VERSION="${VERSION:-latest}"                 # "latest" or a tag like v0.27.0; also --version
BIN_DIR="${BIN_DIR:-/usr/local/bin}"         # where the binaries go; also --bin-dir
INSTALL_URL="${INSTALL_URL:-https://get.obserae.com}"

# systemd deployment paths (match obserae.com/docs/operations)
CONF_DIR="/etc/obserae"
CONF_FILE="$CONF_DIR/obserae.yaml"
DATA_ROOT="/var/lib/obserae"
UNIT_FILE="/etc/systemd/system/obserae.service"
SVC_USER="obserae"

# Sigstore keyless identity of obserae's release pipeline (see obserae.com/docs/verify)
COSIGN_ID_REGEX="https://github.com/spartan-conseil/.*"
COSIGN_ISSUER="https://token.actions.githubusercontent.com"

# --- Runtime state -----------------------------------------------------------
CMD=""
STRICT=0
VERIFY_PROV=0
DOWNLOAD_ONLY=0
PURGE=0
ASSUME_YES="${ASSUME_YES:-0}"
SUDO=""
DOWNLOADER=""
ARCH=""
tarball=""
_tmpdir=""

# --- Logging -----------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="$(printf '\033[0m')"; C_INFO="$(printf '\033[1;34m')"
  C_WARN="$(printf '\033[1;33m')"; C_ERR="$(printf '\033[1;31m')"
  C_OK="$(printf '\033[1;32m')"
else
  C_RESET=''; C_INFO=''; C_WARN=''; C_ERR=''; C_OK=''
fi
info() { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2; }
ok()   { printf '%s==>%s %s\n' "$C_OK"   "$C_RESET" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err()  { printf '%serror:%s %s\n'   "$C_ERR"  "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

cleanup() { [ -n "$_tmpdir" ] && rm -rf "$_tmpdir" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

have() { command -v "$1" >/dev/null 2>&1; }
priv() { $SUDO "$@"; }   # run a privileged command (prefixes sudo when not root)

usage() {
  cat >&2 <<EOF
obserae installer

Usage (remote):
  curl -fsSL $INSTALL_URL | sudo sh
  curl -fsSL $INSTALL_URL | sudo sh -s -- [command] [options]

Commands:
  install      Download, verify and deploy obserae as a systemd service (default)
  uninstall    Stop and remove the service and binaries (--purge also wipes data)
  help         Show this help

Options:
  --version REF        Release tag to install (default: latest), e.g. v0.27.0
  --bin-dir PATH       Where to install the binaries (default: /usr/local/bin)
  --verify-provenance  Also verify the SLSA build-provenance attestation (needs cosign)
  --download-only      Download and verify the release, then stop (no install; no root)
  --strict             Fail if cosign is missing or any signature/provenance check fails
  --purge              uninstall: also delete $DATA_ROOT, $CONF_DIR and the '$SVC_USER' user
  --yes, -y            Assume "yes" for confirmations (non-interactive purge)

Environment overrides:
  VERSION, BIN_DIR, REPO_OWNER, REPO_NAME, INSTALL_URL
EOF
}

# --- Argument parsing --------------------------------------------------------
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      install|uninstall)   [ -z "$CMD" ] && CMD="$1" || true ;;
      help|-h|--help)      CMD="help" ;;
      --version)           shift; [ $# -gt 0 ] || die "--version needs a value"; VERSION="$1" ;;
      --version=*)         VERSION="${1#--version=}" ;;
      --bin-dir)           shift; [ $# -gt 0 ] || die "--bin-dir needs a path"; BIN_DIR="$1" ;;
      --bin-dir=*)         BIN_DIR="${1#--bin-dir=}" ;;
      --verify-provenance) VERIFY_PROV=1 ;;
      --download-only)     DOWNLOAD_ONLY=1 ;;
      --strict)            STRICT=1 ;;
      --purge)             PURGE=1 ;;
      --yes|-y)            ASSUME_YES=1 ;;
      --)                  ;;
      -*)                  die "unknown option: $1 (try 'help')" ;;
      *)                   die "unknown argument: $1 (try 'help')" ;;
    esac
    shift
  done
  [ -n "$CMD" ] || CMD="install"
}

# --- Preflight ---------------------------------------------------------------
check_os() {
  [ "$(uname -s)" = "Linux" ] || die "obserae runs on Linux only (this host is $(uname -s))."
}
detect_arch() {
  _m="$(uname -m)"
  case "$_m" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) die "unsupported CPU architecture '$_m' — obserae ships linux amd64 and arm64 only." ;;
  esac
}
detect_downloader() {
  if have curl; then DOWNLOADER="curl"
  elif have wget; then DOWNLOADER="wget"
  else die "need curl or wget to download the release."; fi
}
detect_privilege() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  elif have sudo; then
    SUDO="sudo"
    info "Not running as root — using sudo for privileged steps."
  else
    die "This installer deploys a systemd service and needs root. Re-run:  curl -fsSL $INSTALL_URL | sudo sh"
  fi
}

# dl <url> <dest> — download to a file (fails on HTTP error)
dl() {
  if [ "$DOWNLOADER" = "curl" ]; then curl -fsSL -o "$2" "$1"
  else wget -qO "$2" "$1"; fi
}

release_base() {
  if [ "$VERSION" = "latest" ]; then
    printf '%s' "https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download"
  else
    printf '%s' "https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/$VERSION"
  fi
}

# Best-effort human version for the summary (resolves "latest" via the redirect).
resolve_version_display() {
  case "$VERSION" in latest) ;; *) printf '%s' "$VERSION"; return ;; esac
  if [ "$DOWNLOADER" = "curl" ]; then
    _u="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest" 2>/dev/null || true)"
    case "$_u" in */tag/*) printf '%s' "${_u##*/tag/}"; return ;; esac
  fi
  printf '%s' "latest"
}

# --- Download + verify -------------------------------------------------------
download_release() {
  have mktemp || die "mktemp is required."
  have tar || die "tar is required."
  _tmpdir="$(mktemp -d)"
  _base="$(release_base)"
  tarball="obserae_linux_${ARCH}.tar.gz"
  info "Downloading obserae ($VERSION, linux/$ARCH)…"
  dl "$_base/$tarball"             "$_tmpdir/$tarball"             || die "download failed: $tarball (does release '$VERSION' exist?)"
  dl "$_base/checksums.txt"        "$_tmpdir/checksums.txt"        || die "download failed: checksums.txt"
  dl "$_base/checksums.txt.sig"    "$_tmpdir/checksums.txt.sig"    || die "download failed: checksums.txt.sig"
  dl "$_base/checksums.txt.pem"    "$_tmpdir/checksums.txt.pem"    || die "download failed: checksums.txt.pem"
  if [ "$VERIFY_PROV" = "1" ]; then
    dl "$_base/provenance.intoto.jsonl" "$_tmpdir/provenance.intoto.jsonl" || die "download failed: provenance.intoto.jsonl"
  fi
}

verify_checksum() {
  have sha256sum || die "sha256sum is required for integrity verification."
  _line="$(grep "  ${tarball}$" "$_tmpdir/checksums.txt" || true)"
  [ -n "$_line" ] || die "no checksum entry for $tarball in checksums.txt."
  if ( cd "$_tmpdir" && printf '%s\n' "$_line" | sha256sum -c - ) >/dev/null 2>&1; then
    ok "Integrity OK (SHA256): $tarball"
  else
    die "SHA256 checksum mismatch for $tarball — corrupted or tampered download; aborting."
  fi
}

verify_signature() {
  if have cosign; then
    info "Verifying signature (cosign keyless)…"
    if ( cd "$_tmpdir" && cosign verify-blob checksums.txt \
            --signature checksums.txt.sig \
            --certificate checksums.txt.pem \
            --certificate-identity-regexp "$COSIGN_ID_REGEX" \
            --certificate-oidc-issuer "$COSIGN_ISSUER" ) >/dev/null 2>&1; then
      ok "Signature OK — checksums signed by obserae's release pipeline."
    else
      die "cosign signature verification FAILED — do NOT trust this download. Re-download and retry; if it persists, report via SECURITY.md."
    fi
    if [ "$VERIFY_PROV" = "1" ]; then
      info "Verifying SLSA build provenance…"
      if ( cd "$_tmpdir" && cosign verify-blob-attestation checksums.txt \
              --bundle provenance.intoto.jsonl \
              --type slsaprovenance1 \
              --certificate-identity-regexp "$COSIGN_ID_REGEX" \
              --certificate-oidc-issuer "$COSIGN_ISSUER" ) >/dev/null 2>&1; then
        ok "Provenance OK (SLSA build-provenance)."
      else
        [ "$STRICT" = "1" ] && die "provenance verification FAILED (--strict)."
        warn "provenance verification failed — signature + checksum still OK; continuing."
      fi
    fi
  else
    if [ "$STRICT" = "1" ]; then
      die "cosign not found and --strict set. Install cosign to verify: https://docs.sigstore.dev/system_config/installation/"
    fi
    warn "cosign not found — the binary is NOT cryptographically signature-verified."
    info "The SHA256 checksum WAS verified (integrity). To also prove authenticity + origin, install:"
    info "  - cosign     https://docs.sigstore.dev/system_config/installation/   (Sigstore signature + provenance)"
    info "  - sha256sum  already present on Linux"
    info "Then re-run this installer, or verify by hand: https://obserae.com/docs/verify"
  fi
}

# --- Install -----------------------------------------------------------------
install_binaries() {
  _ex="$_tmpdir/obserae_linux_${ARCH}"
  ( cd "$_tmpdir" && tar -xzf "$tarball" ) || die "failed to extract $tarball."
  [ -f "$_ex/obserae" ] && [ -f "$_ex/obserae-cli" ] || die "archive layout unexpected (binaries missing)."
  if have systemctl && systemctl is-active --quiet obserae 2>/dev/null; then
    info "Stopping the running obserae service for upgrade…"
    priv systemctl stop obserae || true
  fi
  priv install -m 0755 "$_ex/obserae"     "$BIN_DIR/obserae"
  priv install -m 0755 "$_ex/obserae-cli" "$BIN_DIR/obserae-cli"
  ok "Installed obserae and obserae-cli into $BIN_DIR"
}

setup_service() {
  if ! have systemctl; then
    warn "systemd not detected (no systemctl) — skipping service setup."
    warn "Binaries are installed. Run manually: $BIN_DIR/obserae --config <config>. See obserae.com/docs/operations."
    return 0
  fi

  if ! id -u "$SVC_USER" >/dev/null 2>&1; then
    info "Creating system user '$SVC_USER'…"
    priv useradd --system --home "$DATA_ROOT" --shell /usr/sbin/nologin "$SVC_USER"
  fi

  priv install -d -o "$SVC_USER" -g "$SVC_USER" -m 0750 \
    "$DATA_ROOT" "$DATA_ROOT/data" "$DATA_ROOT/db" "$DATA_ROOT/run"

  if [ ! -f "$CONF_FILE" ]; then
    info "Writing default config to $CONF_FILE…"
    priv install -d -m 0755 "$CONF_DIR"
    priv tee "$CONF_FILE" >/dev/null <<'YAML'
listen:
  netflow:
    enabled: true
    address: "0.0.0.0:2055"
  ipfix:
    enabled: true
    address: "0.0.0.0:4739"

storage:
  data_dir: "/var/lib/obserae/data"
  duckdb_path: "/var/lib/obserae/db/obserae.duckdb"
  memory_limit: "50%"

control:
  socket: "/var/lib/obserae/run/obserae.sock"

web:
  enabled: true
  address: "127.0.0.1:8080"

logging:
  verbosity: 0
YAML
  else
    info "Keeping existing config at $CONF_FILE (not overwritten)."
  fi

  if [ ! -f "$UNIT_FILE" ]; then
    info "Installing the systemd unit…"
    priv tee "$UNIT_FILE" >/dev/null <<EOF
[Unit]
Description=obserae NetFlow/IPFIX collector
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=$SVC_USER
Group=$SVC_USER
ExecStart=$BIN_DIR/obserae --config $CONF_FILE
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_ROOT
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
EOF
  else
    info "Keeping existing systemd unit at $UNIT_FILE (not overwritten)."
  fi

  priv systemctl daemon-reload
  info "Enabling and starting obserae…"
  if priv systemctl enable --now obserae; then
    ok "Service 'obserae' is enabled and running."
  else
    warn "Could not start obserae (check: journalctl -u obserae). Binaries and config are in place."
  fi
}

print_next_steps() {
  _ver="$(resolve_version_display)"
  cat <<EOF

${C_OK}obserae installed.${C_RESET}

  Version:  $_ver
  Binaries: $BIN_DIR/obserae , $BIN_DIR/obserae-cli
  Config:   $CONF_FILE
  Data:     $DATA_ROOT
  GUI:      http://127.0.0.1:8080

First-boot admin password (obserae prints it once in the log):
  journalctl -u obserae | grep -i password

IMPORTANT — back up the at-rest master key offline (losing it is unrecoverable):
  $DATA_ROOT/data/masterkey.bin

Service:
  systemctl status obserae
  journalctl -u obserae -f

Point your NetFlow/IPFIX exporters at UDP 2055 / 4739 on this host.
Verify a release yourself anytime: https://obserae.com/docs/verify
Uninstall:  curl -fsSL $INSTALL_URL | sudo sh -s -- uninstall
EOF
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

# --- Commands ----------------------------------------------------------------
cmd_install() {
  check_os
  detect_arch
  detect_downloader
  [ "$DOWNLOAD_ONLY" = "1" ] || detect_privilege
  download_release
  verify_checksum
  verify_signature
  if [ "$DOWNLOAD_ONLY" = "1" ]; then
    ok "Verification complete — release '$VERSION' (linux/$ARCH) is intact. Not installing (--download-only)."
    return 0
  fi
  install_binaries
  setup_service
  print_next_steps
}

cmd_uninstall() {
  detect_privilege
  if have systemctl; then
    if [ -f "$UNIT_FILE" ] || systemctl list-unit-files 2>/dev/null | grep -q '^obserae\.service'; then
      info "Stopping and disabling the obserae service…"
      priv systemctl disable --now obserae >/dev/null 2>&1 || true
      priv rm -f "$UNIT_FILE"
      priv systemctl daemon-reload >/dev/null 2>&1 || true
    fi
  fi
  priv rm -f "$BIN_DIR/obserae" "$BIN_DIR/obserae-cli"
  ok "Removed the binaries and the service unit."
  if [ "$PURGE" = "1" ]; then
    case "$DATA_ROOT" in ""|/|/usr|/etc|/var|/home|"$HOME") die "refusing to purge unsafe path '$DATA_ROOT'." ;; esac
    confirm "PURGE will DELETE all obserae data ($DATA_ROOT), config ($CONF_DIR) and the '$SVC_USER' user. Irreversible. Continue?" \
      || { info "Purge aborted — data and config kept."; return 0; }
    priv rm -rf "$DATA_ROOT" "$CONF_DIR"
    id -u "$SVC_USER" >/dev/null 2>&1 && priv userdel "$SVC_USER" >/dev/null 2>&1 || true
    ok "Purged data, config and the service user."
  else
    info "Kept data and config ($DATA_ROOT, $CONF_DIR). Re-run with --purge to remove them too."
  fi
}

# --- Main --------------------------------------------------------------------
main() {
  parse_args "$@"
  case "$CMD" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    help)      usage ;;
    *)         usage; exit 1 ;;
  esac
}

main "$@"
