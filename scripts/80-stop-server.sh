#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

if ! id "${OMLX_SERVICE_USER}" >/dev/null 2>&1; then
  echo "service user does not exist: ${OMLX_SERVICE_USER}"
  exit 0
fi

if launchctl print "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1; then
  echo "stopping LaunchDaemon ${OMLX_LAUNCHD_LABEL}"
  launchctl bootout "system/${OMLX_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
fi

matches="$(pgrep -u "${OMLX_SERVICE_USER}" -f "${OMLX_VENV}/bin/omlx.*serve" || true)"
if [ -z "${matches}" ]; then
  matches="$(pgrep -u "${OMLX_SERVICE_USER}" -f "omlx.*serve" || true)"
fi
if [ -z "${matches}" ]; then
  matches="$(pgrep -u "${OMLX_SERVICE_USER}" -f "sandbox-exec.*${OMLX_PROFILE}" || true)"
fi

if [ -z "${matches}" ]; then
  echo "no oMLX server processes found for ${OMLX_SERVICE_USER}"
  exit 0
fi

echo "stopping oMLX server process(es): ${matches//$'\n'/ }"
kill ${matches}

for _ in $(seq 1 20); do
  remaining=""
  for pid in ${matches}; do
    if kill -0 "${pid}" 2>/dev/null; then
      remaining="${remaining} ${pid}"
    fi
  done
  if [ -z "${remaining}" ]; then
    echo "stopped"
    exit 0
  fi
  sleep 0.5
done

echo "forcing remaining process(es):${remaining}"
kill -9 ${remaining} 2>/dev/null || true
