#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

cd /

echo "service user:"
id "${OMLX_SERVICE_USER}"

echo
echo "runtime paths:"
for path in "${OMLX_SRC}" "${OMLX_VENV}/bin/python" "${OMLX_VENV}/bin/omlx" "${OMLX_PROFILE}" "${OMLX_MODELS_APPROVED}"; do
  if [ -e "${path}" ]; then
    stat -f '%Su:%Sg %OLp %N' "${path}"
  else
    echo "missing: ${path}"
    exit 1
  fi
done

echo
echo "oMLX source revision:"
as_service_user "${GIT_BIN}" -C "${OMLX_SRC}" describe --tags --always --dirty

echo
echo "oMLX CLI:"
as_service_user "${OMLX_VENV}/bin/omlx" --help | sed -n '1,60p'

echo
echo "Python package import:"
as_service_user "${OMLX_VENV}/bin/python" - <<'PY'
import importlib.metadata
print("omlx", importlib.metadata.version("omlx"))
PY

echo
echo "install verification passed"
