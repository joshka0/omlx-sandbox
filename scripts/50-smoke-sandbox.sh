#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user

cd /

if [ ! -f "${OMLX_PROFILE}" ]; then
  echo "ERROR: missing ${OMLX_PROFILE}. Run scripts/render-sandbox-profile.sh first." >&2
  exit 1
fi

echo "checking profile applies to a trivial command"
sudo -u "${OMLX_SERVICE_USER}" env HOME="${OMLX_HOME}" TMPDIR="${OMLX_TMP}" \
  /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${OMLX_HOME}" \
  /usr/bin/sandbox-exec -f "${OMLX_PROFILE}" /usr/bin/true

echo "checking normal user SSH path is not readable"
if sudo -u "${OMLX_SERVICE_USER}" env HOME="${OMLX_HOME}" TMPDIR="${OMLX_TMP}" \
  /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${OMLX_HOME}" \
  /usr/bin/sandbox-exec -f "${OMLX_PROFILE}" /bin/sh -c 'test -r /Users/joshka/.ssh'; then
  echo "ERROR: sandbox can read /Users/joshka/.ssh" >&2
  exit 1
fi

echo "checking outbound internet is denied"
if sudo -u "${OMLX_SERVICE_USER}" env HOME="${OMLX_HOME}" TMPDIR="${OMLX_TMP}" \
  /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${OMLX_HOME}" \
  /usr/bin/sandbox-exec -f "${OMLX_PROFILE}" /usr/bin/nc -G 3 -z 1.1.1.1 443
then
  echo "ERROR: sandbox allowed outbound TCP to 1.1.1.1:443" >&2
  exit 1
fi

echo "checking outbound localhost is denied"
local_probe_port="$((OMLX_PORT + 1))"
python3 -c 'import socket, sys
port = int(sys.argv[1])
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(1)
s.settimeout(8)
try:
    s.accept()
except Exception:
    pass
' "${local_probe_port}" &
local_probe_pid=$!
sleep 0.5
if sudo -u "${OMLX_SERVICE_USER}" env HOME="${OMLX_HOME}" TMPDIR="${OMLX_TMP}" \
  /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${OMLX_HOME}" \
  /usr/bin/sandbox-exec -f "${OMLX_PROFILE}" /usr/bin/nc -G 3 -z 127.0.0.1 "${local_probe_port}"
then
  kill "${local_probe_pid}" 2>/dev/null || true
  echo "ERROR: sandbox allowed outbound TCP to 127.0.0.1:${local_probe_port}" >&2
  exit 1
fi
kill "${local_probe_pid}" 2>/dev/null || true

echo "sandbox smoke checks passed"
