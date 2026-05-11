#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

case "${OMLX_BASE}" in
  /Users/Shared/omlx-sandbox|/private/tmp/omlx-sandbox|/tmp/omlx-sandbox) ;;
  *)
    echo "ERROR: refusing to teardown unexpected OMLX_BASE: ${OMLX_BASE}" >&2
    exit 1
    ;;
esac

if [ "${YES:-0}" != "1" ]; then
  cat <<EOF
This will remove:
  ${OMLX_BASE}
  local user: ${OMLX_SERVICE_USER}
  local group: ${OMLX_SERVICE_GROUP}

Set YES=1 to confirm:
  sudo YES=1 $0
EOF
  exit 2
fi

"${SCRIPT_DIR}/75-uninstall-launchd-service.sh" || true
"${SCRIPT_DIR}/80-stop-server.sh" || true

if [ -e "${OMLX_BASE}" ]; then
  echo "removing ${OMLX_BASE}"
  rm -rf "${OMLX_BASE}"
fi

if id "${OMLX_SERVICE_USER}" >/dev/null 2>&1; then
  echo "deleting user ${OMLX_SERVICE_USER}"
  dscl . -delete "/Users/${OMLX_SERVICE_USER}" || true
fi

if dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" >/dev/null 2>&1; then
  echo "deleting group ${OMLX_SERVICE_GROUP}"
  dscl . -delete "/Groups/${OMLX_SERVICE_GROUP}" || true
fi

echo "teardown complete"
