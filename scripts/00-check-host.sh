#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

missing=0
for tool in git uv sandbox-exec python3; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "missing: ${tool}" >&2
    missing=1
  else
    echo "ok: ${tool} -> $(command -v "${tool}")"
  fi
done

arch="$(uname -m)"
if [ "${arch}" != "arm64" ]; then
  echo "ERROR: expected arm64 Apple Silicon, got ${arch}" >&2
  missing=1
else
  echo "ok: architecture arm64"
fi

sw_vers

if [ "${missing}" -ne 0 ]; then
  exit 1
fi

echo "base: ${OMLX_BASE}"
echo "service user: ${OMLX_SERVICE_USER}"
echo "omlx version: ${OMLX_VERSION}"
