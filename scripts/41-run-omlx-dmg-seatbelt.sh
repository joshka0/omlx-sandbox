#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

cd /

if [ ! -x "${OMLX_APP_CLI}" ]; then
  echo "ERROR: missing ${OMLX_APP_CLI}. Run scripts/31-install-omlx-dmg.sh first." >&2
  exit 1
fi

if [ ! -f "${OMLX_PROFILE}" ]; then
  echo "ERROR: missing ${OMLX_PROFILE}. Run scripts/render-sandbox-profile.sh first." >&2
  exit 1
fi

write_runtime_settings

echo "starting oMLX DMG runtime under Seatbelt on ${OMLX_HOST}:${OMLX_PORT}"
echo "app: ${OMLX_APP}"
echo "models: ${OMLX_MODELS_APPROVED}"
echo "logs: ${OMLX_LOGS}"

exec sudo -u "${OMLX_SERVICE_USER}" env \
  HOME="${OMLX_HOME}" \
  TMPDIR="${OMLX_TMP}" \
  XDG_CACHE_HOME="${OMLX_CACHE}/xdg" \
  PYTHONDONTWRITEBYTECODE=1 \
  /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${OMLX_HOME}" \
  /usr/bin/sandbox-exec -f "${OMLX_PROFILE}" \
  "${OMLX_APP_CLI}" serve \
    --base-path "${OMLX_SETTINGS_BASE}"
