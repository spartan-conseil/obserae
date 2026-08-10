#!/usr/bin/env bash
# =============================================================================
#  setup-ldap.sh -- provision FreeIPA and point obserae at it (LDAPS)
# -----------------------------------------------------------------------------
#  Run this ONCE after `docker compose up -d`, when the FreeIPA first boot has
#  finished (it can take several minutes). The script is idempotent: re-running
#  it is safe.
#
#  It will:
#    1. wait for the FreeIPA directory to be ready,
#    2. create a non-expiring read-only bind account (a sysaccount),
#    3. create the obserae role groups and a few demo users,
#    4. export the FreeIPA CA certificate,
#    5. configure obserae's LDAP settings (LDAPS + trusted CA) and test it.
#
#  Demo values only -- keep them in sync with docker-compose.yml.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (where docker-compose.yml lives)

ADMIN_PW="ObseraeDemo123"   # FreeIPA admin / Directory Manager
BIND_PW="bindDemo123"       # obserae read-only bind account
USER_PW="Demo12345"         # demo end-user password

# Upper bound on the FreeIPA first boot. Long, because provisioning a CA in a
# container is slow -- but bounded, so a broken directory fails loudly instead
# of hanging the installer forever.
IPA_READY_TIMEOUT="${IPA_READY_TIMEOUT:-900}"

BASE_DN="dc=corp,dc=lan"
BIND_DN="uid=svc-obserae,cn=sysaccounts,cn=etc,${BASE_DN}"
USER_BASE_DN="cn=users,cn=accounts,${BASE_DN}"
GROUP_BASE_DN="cn=groups,cn=accounts,${BASE_DN}"
CA_FILE="freeipa/ca.crt"
# The obserae container runs as non-root and puts its control socket here
# (configs/obserae.docker.yaml), NOT at obserae-cli's default /var/run/obserae.sock.
OBSERAE_SOCK="/var/lib/obserae/run/obserae.sock"

# Docker must be reachable. In this lab that usually means running with sudo;
# fail loudly here instead of hanging silently later.
if ! docker version >/dev/null 2>&1; then
  echo "ERROR: cannot reach the Docker daemon. Run this script with the same" >&2
  echo "       privileges you use for docker, e.g.  sudo $0" >&2
  exit 1
fi

echo "==> Waiting for FreeIPA to finish provisioning (first boot can take several minutes)..."
# `kinit` answers as soon as the KDC is listening -- seconds BEFORE
# ipa-server-install finishes writing the client configuration
# (/etc/ipa/default.conf). Waiting on it alone raced the install: the very next
# `ipa` command died with "IPA client is not configured on this system", and the
# whole provisioning was skipped. `ipa ping` needs the ticket AND that
# configuration, so it is the honest readiness signal for what follows.
_deadline=$(( $(date +%s) + IPA_READY_TIMEOUT ))
until docker compose exec -T freeipa bash -lc \
        "echo '${ADMIN_PW}' | kinit admin && ipa ping" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$_deadline" ]; then
    echo
    echo "ERROR: FreeIPA is still not usable after ${IPA_READY_TIMEOUT}s." >&2
    echo "       Look at what it is doing:  docker compose logs freeipa" >&2
    exit 1
  fi
  printf '.'
  sleep 10
done
echo " ready."

echo "==> Provisioning bind account, role groups and demo users in FreeIPA..."
# The heredoc runs inside the FreeIPA container. It is single-quoted so the host
# does not expand anything; the passwords are passed as positional arguments.
docker compose exec -T freeipa bash -s -- "$ADMIN_PW" "$BIND_PW" "$USER_PW" <<'INNER'
set -euo pipefail
ADMIN_PW="$1"; BIND_PW="$2"; USER_PW="$3"
BASE_DN="dc=corp,dc=lan"
BIND_DN="uid=svc-obserae,cn=sysaccounts,cn=etc,${BASE_DN}"

echo "$ADMIN_PW" | kinit admin

# Read-only bind account. A sysaccount (not a regular user) never expires and is
# meant exactly for service binds, so obserae's LDAP simple bind keeps working.
ldapadd -x -D "cn=Directory Manager" -w "$ADMIN_PW" -c >/dev/null 2>&1 <<LDIF || true
dn: ${BIND_DN}
objectClass: account
objectClass: simplesecurityobject
uid: svc-obserae
userPassword: ${BIND_PW}
passwordExpirationTime: 20380101000000Z
nsIdleTimeout: 0
LDIF

# obserae role groups.
for g in obserae-admins obserae-analysts obserae-auditors; do
  ipa group-show "$g" >/dev/null 2>&1 || ipa group-add "$g" --desc "obserae $g"
done

# Demo users. Their password is set non-expiring so obserae's LDAP simple bind
# works without a forced first-login change.
add_user() {  # uid first last group
  local uid="$1" first="$2" last="$3" group="$4"
  if ! ipa user-show "$uid" >/dev/null 2>&1; then
    printf '%s\n%s\n' "$USER_PW" "$USER_PW" | ipa user-add "$uid" --first "$first" --last "$last" --password
  fi
  ipa user-mod "$uid" --setattr=krbPasswordExpiration=20380101000000Z >/dev/null 2>&1 || true
  ipa group-add-member "$group" --users "$uid" >/dev/null 2>&1 || true
}
add_user alice Alice Martin obserae-admins
add_user bob   Bob   Durand obserae-analysts
add_user carol Carol Petit  obserae-auditors
INNER

echo "==> Exporting the FreeIPA CA certificate to ${CA_FILE}..."
mkdir -p "$(dirname "$CA_FILE")"
docker compose cp freeipa:/etc/ipa/ca.crt "$CA_FILE"

echo "==> Configuring obserae LDAP (LDAPS + trusted FreeIPA CA)..."
docker compose exec -T obserae obserae-cli --socket "$OBSERAE_SOCK" ldap set --enabled \
  --url ldaps://ipa.corp.lan:636 \
  --root-ca "$(cat "$CA_FILE")" \
  --bind-dn "$BIND_DN" \
  --bind-password "$BIND_PW" \
  --user-base-dn "$USER_BASE_DN" \
  --user-filter '(uid=%s)' \
  --username-attr uid \
  --display-attr displayName \
  --group-base-dn "$GROUP_BASE_DN" \
  --map 'obserae-admins=>admin' \
  --map 'obserae-analysts=>analyst' \
  --map 'obserae-auditors=>auditor'

echo "==> Testing the LDAP connection..."
docker compose exec -T obserae obserae-cli --socket "$OBSERAE_SOCK" ldap test

cat <<EOF

Done. Sign in to the obserae UI at http://127.0.0.1:8081 with:
  alice / ${USER_PW}   -> admin
  bob   / ${USER_PW}   -> analyst
  carol / ${USER_PW}   -> auditor

The local 'admin' account stays available as a break-glass login even if
FreeIPA is unreachable.
EOF
