#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

if launchctl print "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1; then
  echo "unloading ${OMLX_LAUNCHD_LABEL}"
  launchctl bootout "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
fi

if [ -f "${OMLX_LAUNCHD_PLIST}" ]; then
  echo "removing ${OMLX_LAUNCHD_PLIST}"
  rm -f "${OMLX_LAUNCHD_PLIST}"
fi

echo "LaunchDaemon uninstalled"
