#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

echo "LaunchDaemon:"
status_out="$(mktemp)"
if launchctl print "system/${OMLX_LAUNCHD_LABEL}" >"${status_out}" 2>&1; then
  awk '
    /^[[:space:]]*state = / ||
    /^[[:space:]]*program = / ||
    /^[[:space:]]*arguments = / ||
    /^[[:space:]]*pid = / ||
    /^[[:space:]]*last exit code = / ||
    /^[[:space:]]*spawn type = / {
      print
    }
  ' "${status_out}"
else
  echo "  not loaded: ${OMLX_LAUNCHD_LABEL}"
fi
rm -f "${status_out}"

echo
echo "processes:"
ps -axo user,pid,ppid,stat,command |
  awk -v user="${OMLX_SERVICE_USER}" '$1 == user && (/[s]andbox-exec.*omlx|[o]mlx.* serve|[o]MLX\.app.* serve/) {print}'

echo
echo "stderr:"
if [ -f "${OMLX_LOGS}/launchd.err.log" ]; then
  tail -80 "${OMLX_LOGS}/launchd.err.log"
else
  echo "  missing ${OMLX_LOGS}/launchd.err.log"
fi

echo
echo "stdout:"
if [ -f "${OMLX_LOGS}/launchd.out.log" ]; then
  tail -80 "${OMLX_LOGS}/launchd.out.log"
else
  echo "  missing ${OMLX_LOGS}/launchd.out.log"
fi
