#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

repo="${REPO:-}"
revision="${REVISION:-main}"
name="${NAME:-}"

if [ -z "${repo}" ]; then
  echo "ERROR: set REPO=org/model" >&2
  exit 2
fi

install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" \
  "${OMLX_MODELS_QUARANTINE}" \
  "${OMLX_CACHE}" \
  "${OMLX_CACHE}/hf" \
  "${OMLX_CACHE}/uv"
install_policy_helpers
install -m 0550 -o root -g "${OMLX_SERVICE_GROUP}" \
  "${SCRIPT_DIR}/hf-download-to-quarantine.py" \
  "${OMLX_POLICY}/hf-download-to-quarantine.py"

if [ -z "${name}" ]; then
  safe_repo="$(printf '%s' "${repo}" | sed -E 's#[/:]+#--#g; s#[^A-Za-z0-9._-]+#-#g')"
  safe_revision="$(printf '%s' "${revision}" | sed -E 's#[/:]+#--#g; s#[^A-Za-z0-9._-]+#-#g')"
  name="${safe_repo}-${safe_revision}-$(date -u '+%Y%m%dT%H%M%SZ')"
else
  name="$(printf '%s' "${name}" | sed -E 's#[/:]+#--#g; s#[^A-Za-z0-9._-]+#-#g')"
fi

dest="${OMLX_MODELS_QUARANTINE}/${name}"
if [ -e "${dest}" ]; then
  echo "ERROR: quarantine destination already exists: ${dest}" >&2
  exit 1
fi

args=(
  --repo "${repo}"
  --revision "${revision}"
  --dest "${dest}"
  --cache-dir "${OMLX_CACHE}/hf"
)

if [ -n "${ALLOW_PATTERNS:-}" ]; then
  args+=(--allow-patterns "${ALLOW_PATTERNS}")
fi
if [ -n "${IGNORE_PATTERNS:-}" ]; then
  args+=(--ignore-patterns "${IGNORE_PATTERNS}")
fi
if [ -n "${HF_TOKEN_FILE:-}" ]; then
  args+=(--token-file "${HF_TOKEN_FILE}")
fi

echo "downloading Hugging Face model to quarantine"
echo "repo: ${repo}"
echo "revision: ${revision}"
echo "dest: ${dest}"

as_service_user env \
  HF_HOME="${OMLX_CACHE}/hf" \
  HF_HUB_CACHE="${OMLX_CACHE}/hf/hub" \
  UV_CACHE_DIR="${OMLX_CACHE}/uv" \
  "${UV_BIN}" run \
    --with huggingface_hub \
    --with hf-xet \
    "${OMLX_POLICY}/hf-download-to-quarantine.py" \
    "${args[@]}"

manifest="${dest}.manifest.json"
scan_exit=0
"${SCRIPT_DIR}/scan-model-dir.py" "${dest}" > "${manifest}" || scan_exit=$?
status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "${manifest}")"
chown "${OMLX_SERVICE_USER}:${OMLX_SERVICE_GROUP}" "${manifest}"
chmod 0600 "${manifest}"

echo "scanner status: ${status}"
echo "manifest: ${manifest}"
echo "candidate: ${dest}"

case "${status}" in
  approved)
    echo "promote with: make promote-model CANDIDATE=${dest}"
    ;;
  approved-with-warnings)
    echo "review warnings, then promote with: make promote-model CANDIDATE=${dest} ALLOW_WARNINGS=1"
    ;;
  denied)
    echo "candidate denied; inspect manifest before deleting or retrying" >&2
    exit "${scan_exit}"
    ;;
esac
