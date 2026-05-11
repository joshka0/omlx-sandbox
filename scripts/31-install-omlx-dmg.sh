#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

cd /

resolve_dmg_path() {
  local path="${DMG:-${OMLX_DMG_PATH:-}}"
  if [ -n "${path}" ]; then
    case "${path}" in
      /*) ;;
      *) path="${PROJECT_DIR}/${path}" ;;
    esac
    printf '%s\n' "${path}"
    return
  fi

  local owner="${SUDO_USER:-}"
  if [ -z "${owner}" ] || [ "${owner}" = "root" ]; then
    owner="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
  fi

  if [ -z "${owner}" ] || [ "${owner}" = "root" ]; then
    return
  fi

  local downloads="/Users/${owner}/Downloads"
  if [ ! -d "${downloads}" ]; then
    return
  fi

  find "${downloads}" -maxdepth 1 -type f -name 'oMLX-*.dmg' -print |
    while IFS= read -r candidate; do
      printf '%s\t%s\n' "$(stat -f '%m' "${candidate}")" "${candidate}"
    done |
    sort -rn |
    head -n 1 |
    cut -f 2-
}

dmg_path="$(resolve_dmg_path)"
if [ -z "${dmg_path}" ] || [ ! -f "${dmg_path}" ]; then
  cat >&2 <<EOF
ERROR: could not find an oMLX DMG.

Pass one explicitly:
  sudo DMG=/path/to/oMLX.dmg $0

Or set OMLX_DMG_PATH in config/runtime.env.local.
EOF
  exit 1
fi

install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_RUN}" "${OMLX_STATE}"
install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_APP_DIR}" "${OMLX_POLICY}"

mount_dir="${OMLX_POLICY}/dmg-mount"
if mount | grep -Fq " on ${mount_dir} "; then
  hdiutil detach "${mount_dir}" >/dev/null
fi
rm -rf "${mount_dir}"
install -d -m 0700 -o root -g wheel "${mount_dir}"

cleanup_mount() {
  hdiutil detach "${mount_dir}" >/dev/null 2>&1 || true
  rmdir "${mount_dir}" >/dev/null 2>&1 || true
}
trap cleanup_mount EXIT

echo "mounting ${dmg_path}"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "${mount_dir}" "${dmg_path}" >/dev/null

src_app="$(find "${mount_dir}" -maxdepth 1 -type d -name 'oMLX.app' -print -quit)"
if [ -z "${src_app}" ]; then
  echo "ERROR: mounted DMG does not contain oMLX.app at its root" >&2
  exit 1
fi

tmp_app="${OMLX_APP}.tmp.$$"
rm -rf "${tmp_app}"

echo "copying app bundle to ${OMLX_APP}"
ditto "${src_app}" "${tmp_app}"

echo "verifying code signature"
codesign --verify --deep --strict "${tmp_app}"

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${tmp_app}/Contents/Info.plist" 2>/dev/null || echo unknown)"
bundle_version="$(plutil -extract CFBundleShortVersionString raw -o - "${tmp_app}/Contents/Info.plist" 2>/dev/null || echo unknown)"
dmg_sha256="$(shasum -a 256 "${dmg_path}" | awk '{print $1}')"

spctl_out="$(mktemp "${OMLX_POLICY}/spctl.XXXXXX")"
if ! spctl --assess --type execute --verbose=4 "${tmp_app}" >"${spctl_out}" 2>&1; then
  echo "warning: spctl assessment did not pass:" >&2
  sed -n '1,8p' "${spctl_out}" >&2 || true
fi
rm -f "${spctl_out}"

rm -rf "${OMLX_APP}"
mv "${tmp_app}" "${OMLX_APP}"

chown -R "root:${OMLX_SERVICE_GROUP}" "${OMLX_APP_DIR}"
chmod 0750 "${OMLX_APP_DIR}"
find "${OMLX_APP}" -type d -exec chmod 0550 {} +
find "${OMLX_APP}" -type f -exec chmod 0440 {} +
find "${OMLX_APP}/Contents/MacOS" -type f -exec chmod 0550 {} +

codesign --verify --deep --strict "${OMLX_APP}"

manifest="${OMLX_POLICY}/dmg-install.txt"
cat > "${manifest}" <<EOF
installed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
dmg_path=${dmg_path}
dmg_sha256=${dmg_sha256}
bundle_id=${bundle_id}
bundle_version=${bundle_version}
app_path=${OMLX_APP}
EOF
chown "root:${OMLX_SERVICE_GROUP}" "${manifest}"
chmod 0440 "${manifest}"

echo "installed ${bundle_id} ${bundle_version} at ${OMLX_APP}"
echo "recorded ${manifest}"
