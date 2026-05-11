#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${PROJECT_DIR}/config/runtime.env.local" ]; then
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/config/runtime.env.local"
elif [ -f "${PROJECT_DIR}/config/runtime.env.example" ]; then
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/config/runtime.env.example"
fi

: "${OMLX_SERVICE_USER:=omlxsvc}"
: "${OMLX_SERVICE_GROUP:=_omlxsvc}"
: "${OMLX_VERSION:=v0.3.8}"
: "${OMLX_BASE:=/Users/Shared/omlx-sandbox}"
: "${OMLX_HOST:=127.0.0.1}"
: "${OMLX_PORT:=18000}"
: "${OMLX_MAX_PROCESS_MEMORY:=70%}"
: "${OMLX_MAX_MODEL_MEMORY:=48GB}"
: "${OMLX_MAX_CONCURRENT_REQUESTS:=2}"
: "${OMLX_API_KEY_FILE:=${OMLX_BASE}/state/api-key}"
: "${OMLX_DMG_PATH:=}"
: "${OMLX_RUNTIME:=source}"
: "${OMLX_LAUNCHD_LABEL:=com.local.omlx-sandbox}"
: "${OMLX_START_TIMEOUT_SECONDS:=120}"

OMLX_SRC="${OMLX_BASE}/src/omlx"
OMLX_VENV="${OMLX_BASE}/venv"
OMLX_PYTHONS="${OMLX_BASE}/pythons"
OMLX_APP_DIR="${OMLX_BASE}/app"
OMLX_APP="${OMLX_APP_DIR}/oMLX.app"
OMLX_APP_CLI="${OMLX_APP}/Contents/MacOS/omlx-cli"
OMLX_HOME="${OMLX_BASE}/home"
OMLX_SETTINGS_BASE="${OMLX_HOME}/.omlx"
OMLX_CACHE="${OMLX_BASE}/cache"
OMLX_LOGS="${OMLX_BASE}/logs"
OMLX_TMP="${OMLX_BASE}/tmp"
OMLX_RUN="${OMLX_BASE}/run"
OMLX_STATE="${OMLX_BASE}/state"
OMLX_POLICY="${OMLX_BASE}/policy"
OMLX_MODELS_QUARANTINE="${OMLX_BASE}/models-quarantine"
OMLX_MODELS_APPROVED="${OMLX_BASE}/models-approved"
OMLX_PROFILE="${OMLX_POLICY}/omlx.sb"
OMLX_RUNTIME_SETTINGS_HELPER="${OMLX_POLICY}/write-runtime-settings.py"
OMLX_LAUNCHD_PLIST="/Library/LaunchDaemons/${OMLX_LAUNCHD_LABEL}.plist"

if [ -z "${GIT_BIN:-}" ]; then
  if [ -x /opt/homebrew/bin/git ]; then
    GIT_BIN=/opt/homebrew/bin/git
  else
    GIT_BIN="$(command -v git)"
  fi
fi

if [ -z "${UV_BIN:-}" ]; then
  if [ -x /opt/homebrew/bin/uv ]; then
    UV_BIN=/opt/homebrew/bin/uv
  else
    UV_BIN="$(command -v uv)"
  fi
fi

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: rerun with sudo: $0" >&2
    exit 1
  fi
}

require_service_user() {
  if ! id "${OMLX_SERVICE_USER}" >/dev/null 2>&1; then
    echo "ERROR: service user '${OMLX_SERVICE_USER}' does not exist." >&2
    echo "Run scripts/10-create-service-user.sh first." >&2
    exit 1
  fi
}

require_service_group() {
  if ! dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" >/dev/null 2>&1; then
    echo "ERROR: service group '${OMLX_SERVICE_GROUP}' does not exist." >&2
    echo "Run scripts/11-harden-service-user.sh first." >&2
    exit 1
  fi
}

as_service_user() {
  require_service_user
  if [ "$(id -un)" = "${OMLX_SERVICE_USER}" ]; then
    cd "${OMLX_HOME}"
    HOME="${OMLX_HOME}" TMPDIR="${OMLX_TMP}" "$@"
  else
    (
      cd /
      sudo -u "${OMLX_SERVICE_USER}" env \
        HOME="${OMLX_HOME}" \
        TMPDIR="${OMLX_TMP}" \
        XDG_CACHE_HOME="${OMLX_CACHE}/xdg" \
        /bin/sh -c 'cd "$1" && shift && exec "$@"' sh "${OMLX_HOME}" "$@"
    )
  fi
}

ensure_api_key() {
  if [ ! -s "${OMLX_API_KEY_FILE}" ]; then
    require_service_user
    require_service_group
    if [ "$(id -u)" -eq 0 ]; then
      install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_STATE}"
    fi
    as_service_user /bin/sh -c 'umask 077; /usr/bin/openssl rand -hex 32 > "$1"; chmod 0600 "$1"' sh "${OMLX_API_KEY_FILE}"
    echo "created API key file at ${OMLX_API_KEY_FILE}"
  fi
}

install_policy_helpers() {
  require_service_group
  if [ "$(id -u)" -ne 0 ]; then
    return
  fi
  install -d -m 0750 -o root -g "${OMLX_SERVICE_GROUP}" "${OMLX_POLICY}"
  install -m 0550 -o root -g "${OMLX_SERVICE_GROUP}" "${SCRIPT_DIR}/write-runtime-settings.py" "${OMLX_RUNTIME_SETTINGS_HELPER}"
}

write_runtime_settings() {
  ensure_api_key
  install_policy_helpers
  as_service_user /bin/mkdir -p "${OMLX_SETTINGS_BASE}"
  as_service_user "${OMLX_RUNTIME_SETTINGS_HELPER}" \
    --settings-file "${OMLX_SETTINGS_BASE}/settings.json" \
    --api-key-file "${OMLX_API_KEY_FILE}" \
    --host "${OMLX_HOST}" \
    --port "${OMLX_PORT}" \
    --model-dir "${OMLX_MODELS_APPROVED}" \
    --cache-dir "${OMLX_CACHE}/ssd" \
    --log-dir "${OMLX_LOGS}" \
    --max-process-memory "${OMLX_MAX_PROCESS_MEMORY}" \
    --max-model-memory "${OMLX_MAX_MODEL_MEMORY}" \
    --max-concurrent-requests "${OMLX_MAX_CONCURRENT_REQUESTS}"
  as_service_user /bin/chmod 0600 "${OMLX_SETTINGS_BASE}/settings.json"
}

launchd_stdout_log() {
  printf '%s\n' "${OMLX_LOGS}/launchd.out.log"
}

launchd_stderr_log() {
  printf '%s\n' "${OMLX_LOGS}/launchd.err.log"
}

prepare_launchd_logs() {
  require_service_user
  require_service_group
  if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0700 -o "${OMLX_SERVICE_USER}" -g "${OMLX_SERVICE_GROUP}" "${OMLX_LOGS}"
  fi
  as_service_user /usr/bin/touch "$(launchd_stdout_log)" "$(launchd_stderr_log)"
  as_service_user /bin/chmod 0600 "$(launchd_stdout_log)" "$(launchd_stderr_log)"
}

truncate_launchd_logs() {
  prepare_launchd_logs
  as_service_user /bin/sh -c ': > "$1"; : > "$2"' sh "$(launchd_stdout_log)" "$(launchd_stderr_log)"
}

curl_with_api_key() {
  local api_key="$1"
  shift
  printf 'header = "Authorization: Bearer %s"\n' "${api_key}" |
    curl -K - "$@"
}

runtime_executable() {
  case "${1:-${OMLX_RUNTIME}}" in
    source) printf '%s\n' "${OMLX_VENV}/bin/omlx" ;;
    dmg) printf '%s\n' "${OMLX_APP_CLI}" ;;
    *)
      echo "ERROR: unsupported OMLX runtime '${1:-${OMLX_RUNTIME}}' (expected source or dmg)" >&2
      return 1
      ;;
  esac
}

require_runtime_executable() {
  local runtime="${1:-${OMLX_RUNTIME}}"
  local executable
  executable="$(runtime_executable "${runtime}")"
  if [ ! -x "${executable}" ]; then
    case "${runtime}" in
      source) echo "ERROR: missing ${executable}. Run scripts/30-install-omlx-source.sh first." >&2 ;;
      dmg) echo "ERROR: missing ${executable}. Run scripts/31-install-omlx-dmg.sh first." >&2 ;;
      *) echo "ERROR: missing runtime executable ${executable}" >&2 ;;
    esac
    return 1
  fi
}
