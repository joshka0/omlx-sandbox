#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

template="${PROJECT_DIR}/sandbox/omlx.sbpl.template"
if [ ! -f "${template}" ]; then
  echo "ERROR: missing template ${template}" >&2
  exit 1
fi

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_POLICY}"
install_policy_helpers
tmp_profile="${OMLX_PROFILE}.tmp.$$"
sed "s|__OMLX_BASE__|$(escape_sed "${OMLX_BASE}")|g" "${template}" > "${tmp_profile}"
chown "root:${OMLX_SERVICE_GROUP}" "${tmp_profile}"
chmod 0440 "${tmp_profile}"
mv "${tmp_profile}" "${OMLX_PROFILE}"

echo "rendered ${OMLX_PROFILE}"
