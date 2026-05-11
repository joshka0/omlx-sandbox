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

api_key="$(cat "${OMLX_API_KEY_FILE}")"
base_url="http://${OMLX_HOST}:${OMLX_PORT}"

echo "checking unauthenticated request is rejected"
unauth_status="$(curl -sS -o /dev/null -w '%{http_code}' "${base_url}/v1/models" || true)"
echo "unauthenticated status: ${unauth_status}"
case "${unauth_status}" in
  401|403) ;;
  *)
    echo "ERROR: expected unauthenticated request to be rejected" >&2
    exit 1
    ;;
esac

echo "checking authenticated /v1/models"
curl_with_api_key "${api_key}" -sS "${base_url}/v1/models"
echo
echo "server API test passed"
