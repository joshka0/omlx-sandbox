#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

url="http://${OMLX_HOST}:${OMLX_PORT}/admin"

if [ -x /usr/bin/open ]; then
  /usr/bin/open "${url}"
fi

echo "oMLX admin UI: ${url}"
echo "If prompted for an API key, run: make copy-api-key"
