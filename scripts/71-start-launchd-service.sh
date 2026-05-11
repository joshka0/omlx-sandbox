#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

if [ ! -f "${OMLX_LAUNCHD_PLIST}" ]; then
  echo "ERROR: missing ${OMLX_LAUNCHD_PLIST}. Run make run or make install-service first." >&2
  exit 1
fi

if [ ! -f "${OMLX_PROFILE}" ]; then
  echo "rendering missing Seatbelt profile at ${OMLX_PROFILE}"
  "${SCRIPT_DIR}/render-sandbox-profile.sh"
fi

write_runtime_settings
truncate_launchd_logs

if ! launchctl print "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1; then
  launchctl bootstrap system "${OMLX_LAUNCHD_PLIST}"
fi

launchctl enable "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "system/${OMLX_LAUNCHD_LABEL}"

echo "started ${OMLX_LAUNCHD_LABEL}"
base_url="http://${OMLX_HOST}:${OMLX_PORT}"
api_key="$(/bin/cat "${OMLX_API_KEY_FILE}")"
ready=0
case "${OMLX_START_TIMEOUT_SECONDS}" in
  ''|*[!0-9]*)
    echo "ERROR: OMLX_START_TIMEOUT_SECONDS must be an integer, got '${OMLX_START_TIMEOUT_SECONDS}'" >&2
    exit 1
    ;;
esac

for elapsed in $(seq 1 "${OMLX_START_TIMEOUT_SECONDS}"); do
  status="$(curl_with_api_key "${api_key}" -sS -o /dev/null -w '%{http_code}' "${base_url}/v1/models" 2>/dev/null || true)"
  case "${status}" in
    200)
      echo "server reachable at ${base_url} (${status})"
      ready=1
      break
      ;;
    401|403)
      echo "server reachable at ${base_url}, but authenticated probe was rejected (${status})" >&2
      break
      ;;
  esac
  if [ $((elapsed % 15)) -eq 0 ]; then
    echo "waiting for server at ${base_url} (${elapsed}/${OMLX_START_TIMEOUT_SECONDS}s)"
  fi
  sleep 1
done

if [ "${ready}" -ne 1 ]; then
  echo "server did not become reachable at ${base_url} within ${OMLX_START_TIMEOUT_SECONDS}s; check status/logs below" >&2
  "${SCRIPT_DIR}/72-status-launchd-service.sh" || true
  exit 1
fi
"${SCRIPT_DIR}/72-status-launchd-service.sh" || true
