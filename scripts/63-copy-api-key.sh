#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

if [ ! -s "${OMLX_API_KEY_FILE}" ]; then
  echo "ERROR: missing API key file: ${OMLX_API_KEY_FILE}" >&2
  exit 1
fi

console_user="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
if [ -z "${console_user}" ] || [ "${console_user}" = "root" ]; then
  echo "ERROR: could not identify the logged-in console user" >&2
  exit 1
fi

console_uid="$(id -u "${console_user}")"
/bin/cat "${OMLX_API_KEY_FILE}" |
  launchctl asuser "${console_uid}" sudo -u "${console_user}" /usr/bin/pbcopy

echo "copied oMLX sandbox API key to ${console_user}'s clipboard"
