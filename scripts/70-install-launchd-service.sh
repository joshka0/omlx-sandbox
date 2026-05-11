#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

runtime="${RUNTIME:-${OMLX_RUNTIME}}"
if [ "${runtime}" = "source" ] && [ ! -x "${OMLX_VENV}/bin/omlx" ]; then
  echo "source runtime missing; installing before LaunchDaemon setup"
  "${SCRIPT_DIR}/30-install-omlx-source.sh"
fi
require_runtime_executable "${runtime}"
if [ "${runtime}" = "source" ]; then
  "${SCRIPT_DIR}/32-freeze-source-runtime.sh"
fi

if [ ! -f "${OMLX_PROFILE}" ]; then
  echo "rendering missing Seatbelt profile at ${OMLX_PROFILE}"
  "${SCRIPT_DIR}/render-sandbox-profile.sh"
fi

write_runtime_settings

prepare_launchd_logs
stdout_path="$(launchd_stdout_log)"
stderr_path="$(launchd_stderr_log)"

executable="$(runtime_executable "${runtime}")"
python_arg=()
if [ "${runtime}" = "source" ]; then
  python_arg=(--python "${OMLX_VENV}/bin/python")
fi
tmp_plist="$(mktemp "${OMLX_POLICY}/${OMLX_LAUNCHD_LABEL}.plist.XXXXXX")"
"${SCRIPT_DIR}/render-launchd-plist.py" \
  --label "${OMLX_LAUNCHD_LABEL}" \
  --user "${OMLX_SERVICE_USER}" \
  --group "${OMLX_SERVICE_GROUP}" \
  --home "${OMLX_HOME}" \
  --tmp "${OMLX_TMP}" \
  --xdg-cache "${OMLX_CACHE}/xdg" \
  --profile "${OMLX_PROFILE}" \
  --executable "${executable}" \
  "${python_arg[@]}" \
  --base-path "${OMLX_SETTINGS_BASE}" \
  --stdout "${stdout_path}" \
  --stderr "${stderr_path}" > "${tmp_plist}"

plutil -lint "${tmp_plist}" >/dev/null

if launchctl print "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1; then
  echo "unloading existing ${OMLX_LAUNCHD_LABEL}"
  launchctl bootout "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
fi

install -m 0644 -o root -g wheel "${tmp_plist}" "${OMLX_LAUNCHD_PLIST}"
rm -f "${tmp_plist}"
launchctl enable "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1 || true

echo "installed LaunchDaemon ${OMLX_LAUNCHD_LABEL}"
echo "runtime: ${runtime}"
echo "plist: ${OMLX_LAUNCHD_PLIST}"
