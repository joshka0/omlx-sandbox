#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <quarantine-model-dir>" >&2
  exit 2
fi

candidate="$1"
if [ ! -d "${candidate}" ]; then
  echo "ERROR: candidate is not a directory: ${candidate}" >&2
  exit 1
fi

candidate_abs="$(cd "${candidate}" && pwd)"
case "${candidate_abs}" in
  "${OMLX_MODELS_QUARANTINE}"/*) ;;
  *)
    echo "ERROR: candidate must be under ${OMLX_MODELS_QUARANTINE}" >&2
    exit 1
    ;;
esac

name="$(basename "${candidate_abs}")"
dest="${OMLX_MODELS_APPROVED}/${name}"
manifest="${candidate_abs}.manifest.json"

if [ -e "${dest}" ]; then
  echo "ERROR: approved model already exists: ${dest}" >&2
  exit 1
fi

scan_exit=0
"${SCRIPT_DIR}/scan-model-dir.py" "${candidate_abs}" > "${manifest}" || scan_exit=$?
status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "${manifest}")"

if [ "${status}" = "denied" ]; then
  echo "ERROR: scanner denied candidate. See ${manifest}" >&2
  exit "${scan_exit}"
fi

if [ "${status}" = "approved-with-warnings" ] && [ "${ALLOW_WARNINGS:-0}" != "1" ]; then
  echo "ERROR: scanner produced warnings. Review ${manifest}, then rerun with ALLOW_WARNINGS=1 if acceptable." >&2
  exit 1
fi

mkdir -p "${OMLX_MODELS_APPROVED}"
rsync -a --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r "${candidate_abs}/" "${dest}/"
cp "${manifest}" "${dest}.manifest.json"

echo "promoted ${candidate_abs} -> ${dest}"
