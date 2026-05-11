#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_BASE}"
install -d -m 0750 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_SRC%/*}"
install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_APP_DIR}" "${OMLX_POLICY}"
install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_MODELS_APPROVED}"
install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_MODELS_QUARANTINE}"
install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_HOME}" "${OMLX_CACHE}" "${OMLX_LOGS}" "${OMLX_TMP}" "${OMLX_RUN}" "${OMLX_STATE}" "${OMLX_PYTHONS}" "${OMLX_VENV}"

chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_APP_DIR}"
chmod 0750 "${OMLX_APP_DIR}"

chown "root:${OMLX_SERVICE_GROUP}" "${OMLX_POLICY}"
chmod 0750 "${OMLX_POLICY}"
install_policy_helpers

if [ -d "${OMLX_APP}" ]; then
  chown -R "root:${OMLX_SERVICE_GROUP}" "${OMLX_APP}"
  find "${OMLX_APP}" -type d -exec chmod 0550 {} +
  find "${OMLX_APP}" -type f -exec chmod 0440 {} +
  find "${OMLX_APP}/Contents/MacOS" -type f -exec chmod 0550 {} +
fi

echo "created sandbox layout at ${OMLX_BASE}"
find "${OMLX_BASE}" -maxdepth 1 -mindepth 1 -print | sort
