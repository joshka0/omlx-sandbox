#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

cd /

if [ ! -x "${OMLX_VENV}/bin/omlx" ]; then
  echo "ERROR: missing ${OMLX_VENV}/bin/omlx. Run scripts/30-install-omlx-source.sh first." >&2
  exit 1
fi

install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_POLICY}"

for path in "${OMLX_SRC%/*}" "${OMLX_SRC}" "${OMLX_VENV}" "${OMLX_PYTHONS}"; do
  if [ ! -e "${path}" ]; then
    continue
  fi
  chown -R "root:${OMLX_SERVICE_GROUP}" "${path}"
  find "${path}" -type d -exec chmod 0550 {} +
  find "${path}" -type f -exec chmod 0440 {} +
  while IFS= read -r bin_dir; do
    find "${bin_dir}" -type f -exec chmod 0550 {} +
  done < <(find "${path}" -type d -name bin -print)
done

stamp="${OMLX_POLICY}/source-runtime-frozen"
{
  echo "frozen_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "source=${OMLX_SRC}"
  echo "venv=${OMLX_VENV}"
  echo "pythons=${OMLX_PYTHONS}"
} > "${stamp}"
chown "root:${OMLX_SERVICE_GROUP}" "${stamp}"
chmod 0440 "${stamp}"

echo "froze source runtime as root-owned read-only"
