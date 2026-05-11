#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if id "${OMLX_SERVICE_USER}" >/dev/null 2>&1; then
  echo "service user already exists: ${OMLX_SERVICE_USER}"
  exit 0
fi

if [ "${APPLY:-0}" != "1" ]; then
  cat <<EOF
DRY RUN

Would create hidden macOS service user:
  user: ${OMLX_SERVICE_USER}
  group: ${OMLX_SERVICE_GROUP}
  shell: /usr/bin/false
  home: /var/empty

Run this to apply:
  sudo APPLY=1 $0
EOF
  exit 0
fi

require_root

uid=""
for candidate in $(seq 401 499); do
  if ! dscl . -list /Users UniqueID | awk '{print $2}' | grep -qx "${candidate}"; then
    uid="${candidate}"
    break
  fi
done

if [ -z "${uid}" ]; then
  echo "ERROR: no free hidden UID in 401..499" >&2
  exit 1
fi

gid=""
if dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" >/dev/null 2>&1; then
  gid="$(dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" PrimaryGroupID | awk '{print $2}')"
else
  for candidate in $(seq 401 499); do
    if ! dscl . -list /Groups PrimaryGroupID | awk '{print $2}' | grep -qx "${candidate}"; then
      gid="${candidate}"
      break
    fi
  done
  if [ -z "${gid}" ]; then
    echo "ERROR: no free hidden GID in 401..499" >&2
    exit 1
  fi
  dscl . -create "/Groups/${OMLX_SERVICE_GROUP}"
  dscl . -create "/Groups/${OMLX_SERVICE_GROUP}" RealName "oMLX Service"
  dscl . -create "/Groups/${OMLX_SERVICE_GROUP}" PrimaryGroupID "${gid}"
  dscl . -create "/Groups/${OMLX_SERVICE_GROUP}" Password "*"
fi

dscl . -create "/Users/${OMLX_SERVICE_USER}"
dscl . -create "/Users/${OMLX_SERVICE_USER}" UserShell /usr/bin/false
dscl . -create "/Users/${OMLX_SERVICE_USER}" RealName "oMLX Service"
dscl . -create "/Users/${OMLX_SERVICE_USER}" UniqueID "${uid}"
dscl . -create "/Users/${OMLX_SERVICE_USER}" PrimaryGroupID "${gid}"
dscl . -create "/Users/${OMLX_SERVICE_USER}" NFSHomeDirectory /var/empty
dscl . -create "/Users/${OMLX_SERVICE_USER}" IsHidden 1
if [ "${LOCK_LOGIN:-0}" = "1" ]; then
  dscl . -create "/Users/${OMLX_SERVICE_USER}" AuthenticationAuthority ";DisabledUser;" || true
  dscl . -create "/Users/${OMLX_SERVICE_USER}" Password "*" || true
fi
dscl . -append "/Groups/${OMLX_SERVICE_GROUP}" GroupMembership "${OMLX_SERVICE_USER}" 2>/dev/null || true

echo "created service user ${OMLX_SERVICE_USER} uid=${uid} gid=${gid}"
