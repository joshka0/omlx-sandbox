#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user

if dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" >/dev/null 2>&1; then
  gid="$(dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" PrimaryGroupID | awk '{print $2}')"
else
  gid=""
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

dscl . -create "/Users/${OMLX_SERVICE_USER}" PrimaryGroupID "${gid}"
dscl . -create "/Users/${OMLX_SERVICE_USER}" UserShell /usr/bin/false
dscl . -create "/Users/${OMLX_SERVICE_USER}" NFSHomeDirectory /var/empty
dscl . -create "/Users/${OMLX_SERVICE_USER}" IsHidden 1
dscl . -append "/Groups/${OMLX_SERVICE_GROUP}" GroupMembership "${OMLX_SERVICE_USER}" 2>/dev/null || true

if [ "${LOCK_LOGIN:-0}" = "1" ]; then
  dscl . -create "/Users/${OMLX_SERVICE_USER}" AuthenticationAuthority ";DisabledUser;" || true
  dscl . -create "/Users/${OMLX_SERVICE_USER}" Password "*" || true
fi

if command -v dseditgroup >/dev/null 2>&1; then
  dseditgroup -o edit -d "${OMLX_SERVICE_USER}" -t user staff >/dev/null 2>&1 || true
  dseditgroup -o edit -d "${OMLX_SERVICE_USER}" -t user _lpoperator >/dev/null 2>&1 || true
fi

if [ -d "${OMLX_BASE}" ]; then
  chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_BASE}"
  chmod 0750 "${OMLX_BASE}"
  for path in "${OMLX_HOME}" "${OMLX_CACHE}" "${OMLX_LOGS}" "${OMLX_TMP}" "${OMLX_RUN}" "${OMLX_STATE}" "${OMLX_MODELS_QUARANTINE}" "${OMLX_MODELS_APPROVED}"; do
    if [ -d "${path}" ]; then
      chown "${OMLX_SERVICE_USER}:${OMLX_SERVICE_GROUP}" "${path}"
      chmod 0700 "${path}"
    fi
  done
  if [ -d "${OMLX_SRC%/*}" ]; then
    if [ -e "${OMLX_SRC}" ] || [ -f "${OMLX_POLICY}/source-runtime-frozen" ]; then
      chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_SRC%/*}"
      chmod 0750 "${OMLX_SRC%/*}"
    else
      chown "${OMLX_SERVICE_USER}:${OMLX_SERVICE_GROUP}" "${OMLX_SRC%/*}"
      chmod 0700 "${OMLX_SRC%/*}"
    fi
  fi
  if [ -d "${OMLX_PYTHONS}" ]; then
    if [ -f "${OMLX_POLICY}/source-runtime-frozen" ]; then
      for path in "${OMLX_PYTHONS}" "${OMLX_VENV}"; do
        if [ -d "${path}" ]; then
          chown -R "root:${OMLX_SERVICE_GROUP}" "${path}"
          find "${path}" -type d -exec chmod 0550 {} +
          find "${path}" -type f -perm -111 -exec chmod 0550 {} +
          find "${path}" -type f ! -perm -111 -exec chmod 0440 {} +
        fi
      done
    else
      for path in "${OMLX_PYTHONS}" "${OMLX_VENV}"; do
        if [ -d "${path}" ]; then
          chown "${OMLX_SERVICE_USER}:${OMLX_SERVICE_GROUP}" "${path}"
          chmod 0700 "${path}"
        fi
      done
    fi
  fi
  if [ -d "${OMLX_POLICY}" ]; then
    chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_POLICY}"
    chmod 0750 "${OMLX_POLICY}"
    install_policy_helpers
  fi
  if [ -f "${OMLX_PROFILE}" ]; then
    chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_PROFILE}"
    chmod 0440 "${OMLX_PROFILE}"
  fi
  if [ -d "${OMLX_APP_DIR}" ]; then
    chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_APP_DIR}"
    chmod 0750 "${OMLX_APP_DIR}"
  fi
  if [ -d "${OMLX_APP}" ]; then
    chown -R "root:${OMLX_SERVICE_GROUP}" "${OMLX_APP}"
    find "${OMLX_APP}" -type d -exec chmod 0550 {} +
    find "${OMLX_APP}" -type f -exec chmod 0440 {} +
    find "${OMLX_APP}/Contents/MacOS" -type f -exec chmod 0550 {} +
  fi
fi

id "${OMLX_SERVICE_USER}"
dscl . -read "/Users/${OMLX_SERVICE_USER}" UniqueID PrimaryGroupID NFSHomeDirectory UserShell IsHidden
dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" PrimaryGroupID RealName
dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" GroupMembership 2>/dev/null || true
