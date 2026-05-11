#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

cd /

if [ ! -d "${OMLX_APP}" ]; then
  echo "ERROR: missing ${OMLX_APP}. Run scripts/31-install-omlx-dmg.sh first." >&2
  exit 1
fi

if [ ! -x "${OMLX_APP_CLI}" ]; then
  echo "ERROR: missing executable ${OMLX_APP_CLI}" >&2
  exit 1
fi

if [ ! -f "${OMLX_PROFILE}" ]; then
  echo "ERROR: missing ${OMLX_PROFILE}. Run scripts/render-sandbox-profile.sh first." >&2
  exit 1
fi

echo "service user:"
id "${OMLX_SERVICE_USER}"

echo
echo "DMG runtime paths:"
for path in "${OMLX_APP}" "${OMLX_APP_CLI}" "${OMLX_PROFILE}" "${OMLX_MODELS_APPROVED}"; do
  if [ -e "${path}" ]; then
    stat -f '%Su:%Sg %OLp %N' "${path}"
  else
    echo "missing: ${path}"
    exit 1
  fi
done

echo
echo "bundle metadata:"
plutil -p "${OMLX_APP}/Contents/Info.plist" | sed -n '1,40p'

echo
echo "code signature:"
codesign --verify --deep --strict --verbose=2 "${OMLX_APP}"

echo
echo "oMLX DMG CLI:"
as_service_user "${OMLX_APP_CLI}" --help | sed -n '1,60p'

echo
echo "oMLX DMG CLI under Seatbelt:"
as_service_user /usr/bin/sandbox-exec -f "${OMLX_PROFILE}" "${OMLX_APP_CLI}" --help | sed -n '1,30p'

echo
echo "DMG install verification passed"
