#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root
require_service_user
require_service_group

failures=0
warnings=0

pass() {
  echo "PASS: $*"
}

warn() {
  warnings=$((warnings + 1))
  echo "WARN: $*" >&2
}

fail() {
  failures=$((failures + 1))
  echo "FAIL: $*" >&2
}

attr_value() {
  dscl . -read "/Users/${OMLX_SERVICE_USER}" "$1" 2>/dev/null | awk 'NR == 1 {print $2}'
}

echo "auditing root-escalation controls for ${OMLX_SERVICE_USER}"

uid="$(id -u "${OMLX_SERVICE_USER}")"
gid="$(id -g "${OMLX_SERVICE_USER}")"
primary_gid="$(dscl . -read "/Groups/${OMLX_SERVICE_GROUP}" PrimaryGroupID | awk '{print $2}')"

if [ "${uid}" = "0" ]; then
  fail "service user UID is root"
else
  pass "service user UID is ${uid}"
fi

if [ "${gid}" != "${primary_gid}" ]; then
  fail "service user primary GID ${gid} does not match ${OMLX_SERVICE_GROUP} GID ${primary_gid}"
else
  pass "service user primary group is ${OMLX_SERVICE_GROUP}"
fi

groups="$(id -Gn "${OMLX_SERVICE_USER}")"
for forbidden in admin wheel staff _lpadmin; do
  case " ${groups} " in
    *" ${forbidden} "*) fail "service user is in forbidden group ${forbidden}" ;;
    *) pass "service user is not in ${forbidden}" ;;
  esac
done

shell="$(attr_value UserShell)"
home="$(attr_value NFSHomeDirectory)"
hidden="$(attr_value IsHidden)"

[ "${shell}" = "/usr/bin/false" ] && pass "login shell is /usr/bin/false" || fail "login shell is ${shell}"
[ "${home}" = "/var/empty" ] && pass "directory-service home is /var/empty" || fail "directory-service home is ${home}"
[ "${hidden}" = "1" ] && pass "account is hidden" || fail "account IsHidden is ${hidden:-unset}"

sudo_test_out="$(mktemp)"
if sudo -n -u "${OMLX_SERVICE_USER}" /usr/bin/sudo -n /usr/bin/id -u >"${sudo_test_out}" 2>&1; then
  if grep -qx '0' "${sudo_test_out}"; then
    fail "service user can run sudo as root without a password"
  else
    fail "service user sudo command unexpectedly succeeded"
  fi
else
  pass "service user has no non-interactive sudo path"
fi
rm -f "${sudo_test_out}"

if [ -d "${OMLX_BASE}" ]; then
  if find "${OMLX_BASE}" \( -perm -4000 -o -perm -2000 \) -print -quit | grep -q .; then
    fail "setuid/setgid file exists under ${OMLX_BASE}"
    find "${OMLX_BASE}" \( -perm -4000 -o -perm -2000 \) -print >&2
  else
    pass "no setuid/setgid files under ${OMLX_BASE}"
  fi

  if find "${OMLX_BASE}" -user root \( -perm -020 -o -perm -002 \) -print -quit | grep -q .; then
    fail "root-owned writable path exists under ${OMLX_BASE}"
    find "${OMLX_BASE}" -user root \( -perm -020 -o -perm -002 \) -print >&2
  else
    pass "no root-owned group/world-writable paths under ${OMLX_BASE}"
  fi
else
  fail "missing sandbox base ${OMLX_BASE}"
fi

if [ -f "${OMLX_PROFILE}" ]; then
  owner_group_mode="$(stat -f '%Su:%Sg %OLp' "${OMLX_PROFILE}")"
  [ "${owner_group_mode}" = "root:${OMLX_SERVICE_GROUP} 440" ] &&
    pass "Seatbelt profile is root-owned mode 0440" ||
    fail "Seatbelt profile permissions are ${owner_group_mode}"

  if grep -Eq '^[[:space:]]*\(allow[[:space:]]+default' "${OMLX_PROFILE}"; then
    fail "Seatbelt profile contains allow default"
  else
    pass "Seatbelt profile does not allow default"
  fi
else
  fail "missing Seatbelt profile ${OMLX_PROFILE}"
fi

if [ -f "${OMLX_RUNTIME_SETTINGS_HELPER}" ]; then
  helper_owner_group_mode="$(stat -f '%Su:%Sg %OLp' "${OMLX_RUNTIME_SETTINGS_HELPER}")"
  [ "${helper_owner_group_mode}" = "root:${OMLX_SERVICE_GROUP} 550" ] &&
    pass "runtime settings helper is root-owned mode 0550" ||
    fail "runtime settings helper permissions are ${helper_owner_group_mode}"
else
  fail "missing runtime settings helper ${OMLX_RUNTIME_SETTINGS_HELPER}"
fi

if [ -f "${OMLX_LAUNCHD_PLIST}" ]; then
  plist_owner_group_mode="$(stat -f '%Su:%Sg %OLp' "${OMLX_LAUNCHD_PLIST}")"
  [ "${plist_owner_group_mode}" = "root:wheel 644" ] &&
    pass "LaunchDaemon plist is root:wheel mode 0644" ||
    fail "LaunchDaemon plist permissions are ${plist_owner_group_mode}"

  plist_user="$(plutil -extract UserName raw -o - "${OMLX_LAUNCHD_PLIST}" 2>/dev/null || true)"
  plist_group="$(plutil -extract GroupName raw -o - "${OMLX_LAUNCHD_PLIST}" 2>/dev/null || true)"
  plist_initgroups="$(plutil -extract InitGroups raw -o - "${OMLX_LAUNCHD_PLIST}" 2>/dev/null || true)"
  [ "${plist_user}" = "${OMLX_SERVICE_USER}" ] &&
    pass "LaunchDaemon UserName is ${OMLX_SERVICE_USER}" ||
    fail "LaunchDaemon UserName is ${plist_user:-unset}"
  [ "${plist_group}" = "${OMLX_SERVICE_GROUP}" ] &&
    pass "LaunchDaemon GroupName is ${OMLX_SERVICE_GROUP}" ||
    fail "LaunchDaemon GroupName is ${plist_group:-unset}"
  [ "${plist_initgroups}" = "false" ] &&
    pass "LaunchDaemon disables supplementary group initialization" ||
    fail "LaunchDaemon InitGroups is ${plist_initgroups:-unset}"
fi

if [ -d "${OMLX_APP}" ]; then
  app_owner_group_mode="$(stat -f '%Su:%Sg %OLp' "${OMLX_APP}")"
  case "${app_owner_group_mode}" in
    root:${OMLX_SERVICE_GROUP}\ 55[0-5]) pass "DMG app bundle is root-owned and not writable by service group" ;;
    *) fail "DMG app bundle permissions are ${app_owner_group_mode}" ;;
  esac
fi

if [ -f "${OMLX_POLICY}/source-runtime-frozen" ]; then
  for path in "${OMLX_SRC%/*}" "${OMLX_SRC}" "${OMLX_VENV}" "${OMLX_PYTHONS}"; do
    if [ -e "${path}" ]; then
      owner_group_mode="$(stat -f '%Su:%Sg %OLp' "${path}")"
      case "${owner_group_mode}" in
        root:${OMLX_SERVICE_GROUP}\ 55[0-5]|root:${OMLX_SERVICE_GROUP}\ 750)
          pass "source runtime path is root-owned and not service-writable: ${path}"
          ;;
        *)
          fail "source runtime path permissions are ${owner_group_mode}: ${path}"
          ;;
      esac
    fi
  done
  for path in "${OMLX_VENV}/bin/python" "${OMLX_VENV}/bin/omlx"; do
    if [ -e "${path}" ]; then
      mode="$(stat -f '%OLp' "${path}")"
      case "${mode}" in
        55[0-5]) pass "source runtime entrypoint is executable by service group: ${path}" ;;
        *) fail "source runtime entrypoint mode is ${mode}: ${path}" ;;
      esac
    fi
  done
fi

if [ -s "${OMLX_API_KEY_FILE}" ]; then
  if ps -axo command | grep -F -f "${OMLX_API_KEY_FILE}" >/dev/null; then
    fail "API key is visible in process arguments"
  else
    pass "API key is not visible in process arguments"
  fi
fi

set +e
server_lines="$(ps -axo user,pid,ppid,command | awk -v svc="${OMLX_SERVICE_USER}" '
  /[o]mlx.* serve/ || /[o]MLX\\.app.* serve/ {
    print
    if ($1 == "root") root_seen = 1
    if ($1 != svc && $1 != "root") other_seen = 1
  }
  END {
    if (root_seen) exit 2
    if (other_seen) exit 3
  }
')"
server_status=$?
set -e
if [ -z "${server_lines}" ]; then
  warn "no running oMLX serve process found to audit"
elif [ "${server_status}" -eq 2 ]; then
  warn "root-owned sudo wrapper is present in oMLX process tree; acceptable only for foreground debugging"
elif [ "${server_status}" -eq 3 ]; then
  fail "oMLX serve process is owned by an unexpected user"
else
  pass "running oMLX serve process is not root"
fi

if [ "${failures}" -ne 0 ]; then
  echo "root escape audit failed: ${failures} failure(s), ${warnings} warning(s)" >&2
  exit 1
fi

echo "root escape audit passed: ${warnings} warning(s)"
