#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

cd /

if [ "${REINSTALL:-0}" != "1" ] && [ -f "${OMLX_POLICY}/source-runtime-frozen" ] && [ -x "${OMLX_VENV}/bin/omlx" ]; then
  echo "source runtime already installed and frozen: ${OMLX_VENV}"
  exit 0
fi

needs_mutable_repair=0
if [ "${REINSTALL:-0}" = "1" ] || [ -f "${OMLX_POLICY}/source-runtime-frozen" ] || [ ! -x "${OMLX_VENV}/bin/omlx" ]; then
  needs_mutable_repair=1
fi

repair_mutable_tree() {
  local path="$1"
  if [ ! -e "${path}" ]; then
    return
  fi
  chown -hR "${OMLX_SERVICE_USER}:${OMLX_SERVICE_GROUP}" "${path}"
  find "${path}" -type d -exec chmod 0700 {} +
  find "${path}" -type f -exec chmod 0600 {} +
}

repair_executable_dir() {
  local path="$1"
  if [ -d "${path}" ]; then
    find "${path}" -type f -exec chmod 0700 {} +
  fi
}

if [ "${needs_mutable_repair}" = "1" ]; then
  if [ "${REINSTALL:-0}" = "1" ]; then
    echo "thawing source runtime for reinstall"
  elif [ -f "${OMLX_POLICY}/source-runtime-frozen" ]; then
    echo "thawing incomplete frozen source runtime"
  else
    echo "repairing mutable source runtime permissions"
  fi
  rm -f "${OMLX_POLICY}/source-runtime-frozen"
  repair_mutable_tree "${OMLX_SRC%/*}"
  repair_mutable_tree "${OMLX_VENV}"
  repair_mutable_tree "${OMLX_PYTHONS}"
  repair_executable_dir "${OMLX_VENV}/bin"
  while IFS= read -r bin_dir; do
    repair_executable_dir "${bin_dir}"
  done < <(find "${OMLX_PYTHONS}" -type d -name bin -print 2>/dev/null || true)
fi

install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_BASE}"
install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_SRC%/*}" "${OMLX_PYTHONS}" "${OMLX_VENV}"

if [ -d "${OMLX_SRC}/.git" ]; then
  echo "source already exists: ${OMLX_SRC}"
else
  if [ -e "${OMLX_SRC}" ]; then
    failed_path="${OMLX_SRC}.failed-$(date +%Y%m%d%H%M%S)"
    mv "${OMLX_SRC}" "${failed_path}"
    echo "moved incomplete source tree to ${failed_path}"
  fi
  as_service_user "${GIT_BIN}" clone --depth 1 --branch "${OMLX_VERSION}" https://github.com/jundot/omlx.git "${OMLX_SRC}"
fi

as_service_user env UV_PYTHON_INSTALL_DIR="${OMLX_PYTHONS}" "${UV_BIN}" python install 3.12
if [ ! -x "${OMLX_VENV}/bin/python" ]; then
  as_service_user env UV_PYTHON_INSTALL_DIR="${OMLX_PYTHONS}" "${UV_BIN}" venv "${OMLX_VENV}" --python 3.12
fi

as_service_user "${UV_BIN}" pip install --python "${OMLX_VENV}/bin/python" --upgrade pip
as_service_user "${UV_BIN}" pip install --python "${OMLX_VENV}/bin/python" -e "${OMLX_SRC}"

echo "installed oMLX ${OMLX_VERSION} into ${OMLX_VENV}"
