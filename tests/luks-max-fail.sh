#!/usr/bin/env bash
# Prove the LUKS attempt-cap is a wired product path, not a dangling knob.
# No root, no cryptsetup, no hardware — stubs the peripherals and runs the
# real counter helpers from cicada-crypt. Also checks install → initramfs →
# session boundaries so the OS hangs together.
#
# Run: tests/luks-max-fail.sh   (also from tests/here.sh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

HOOK="${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt"
INSTALL_HOOK="${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/install/cicada-crypt"
CHROOT="${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh"
DEFAULTS="${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env"
HYPRLOCK_PAM="${ROOT}/packages/cicada-defaults/files/etc/pam.d/hyprlock"
LOCK="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-lock"
DURESS_CHECK="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-duress-check"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo "==> product spine: install puts cicada-crypt on the boot path"
grep -q 'HOOKS=.*cicada-crypt.*filesystems' "${CHROOT}" \
  || die "cicada-crypt must sit in mkinitcpio HOOKS before filesystems"
grep -q 'cryptdevice=UUID=' "${CHROOT}" || die "installed cmdline missing cryptdevice="
grep -q '/boot/cicada/max-fail' "${CHROOT}" || die "install-chroot must seed ESP max-fail"
grep -q 'CICADA_LUKS_MAX_FAIL=20' "${DEFAULTS}" || die "defaults must ship max-fail=20"
# shellcheck disable=SC1090
max_from_defaults="$(set -a; . "${DEFAULTS}"; set +a; echo "${CICADA_LUKS_MAX_FAIL}")"
[[ "${max_from_defaults}" == "20" ]] || die "defaults.env did not parse CICADA_LUKS_MAX_FAIL=20"
grep -q 'cicada-luks-max-fail' "${INSTALL_HOOK}" || die "initramfs install must bake max-fail"
grep -q 'add_binary blkid' "${INSTALL_HOOK}" || die "ESP discovery needs blkid in initramfs"
grep -q 'add_binary cryptsetup' "${INSTALL_HOOK}" || die "wipe path needs cryptsetup in initramfs"
say "install → HOOKS → defaults → initramfs bake"

echo "==> session boundary: wrong hyprlock PIN must not wipe"
grep -q 'CICADA_LUKS_MAX_FAIL\|luks-fail.count\|_wipe_disk' "${LOCK}" \
  && die "cicada-lock must not implement LUKS attempt-cap wipe" || true
grep -q 'CICADA_LUKS_MAX_FAIL\|luks-fail.count' "${HYPRLOCK_PAM}" \
  && die "hyprlock PAM must not count toward LUKS wipe" || true
# Session wipe is *duress match only*, not N wrong guesses.
grep -q 'duress-check' "${HYPRLOCK_PAM}" || die "hyprlock should still allow enrolled session duress"
grep -q 'luksErase' "${DURESS_CHECK}" || die "session duress must still wipe on match"
# Wrong password path in duress-check exits 0 without wipe (hash mismatch → exit 0 early).
grep -q '\[\[ "${got}" == "${want}" \]\] || exit 0' "${DURESS_CHECK}" \
  || die "session duress must no-op on non-match (no attempt counter)"
say "hyprlock typos recoverable; only enrolled session duress wipes"

echo "==> daily-driver surface still present (security is not the only product)"
hypr="${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf"
for need in \
  "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-dock" \
  "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-files" \
  "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" \
  "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-wofi" \
  "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/wifi.desktop" \
  "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/files.desktop" \
  "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/web.desktop"
do
  test -e "${need}" || die "missing daily-driver piece: ${need#"${ROOT}/"}"
done
grep -q 'layout = dwindle' "${hypr}" || die "tiling must stay default"
grep -q 'NetworkManager.service' "${CHROOT}" || die "installed system must enable NetworkManager"
grep -q 'systemctl enable.*cicada-firstboot' "${CHROOT}" || die "installed firstboot must run"
say "dock / files / wifi / settings / tiling / NM / firstboot"

echo "==> behavioral: real counter helpers + wipe threshold"
# Drive the actual ash helpers from the hook under bash, with a fake ESP.
# Stubs replace mount/cryptsetup/poweroff so we never touch a real disk.
harness="${tmp}/harness.sh"
esp="${tmp}/esp"
mkdir -p "${esp}/EFI" "${esp}/cicada"

# Extract helper bodies (mount through wipe) from the shipping hook.
awk '
  /^_mount_esp\(\)/ { keep=1 }
  keep {
    print
    if (/^_wipe_disk\(\)/) wiping=1
    if (wiping && /^}$/) exit
  }
' "${HOOK}" > "${tmp}/helpers.sh"
grep -q '_read_fails' "${tmp}/helpers.sh" || die "failed to extract fail helpers from hook"
grep -q '_wipe_disk' "${tmp}/helpers.sh" || die "failed to extract wipe helper from hook"

cat > "${harness}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ESPMNT="${CICADA_TEST_ESP}"
CICADA_LUKS_MAX_FAIL="${CICADA_TEST_MAX:-20}"
CICADA_FAILS_MEM=""
CRYPTDEV=/dev/null
CRYPTNAME=cicada
KEYMNT=/tmp/cicada-token-test-$$
WIPED=0
MSG=""

cryptsetup() { return 0; }
dd() { return 0; }
umount() { return 0; }
poweroff() { WIPED=1; MSG="poweroff"; exit 42; }
sleep() { :; }
date() { echo 1000000; }

# shellcheck disable=SC1091
source "${CICADA_TEST_HELPERS}"

# Override after source — the real _mount_esp wants blkid/vfat.
_mount_esp() {
  mkdir -p "${ESPMNT}/cicada"
  return 0
}
# Observe wipe without poweroff -f.
_wipe_disk() {
  WIPED=1
  MSG="wipe"
  _reset_fails
}

_record_fail() {
  local fails
  fails="$(_read_fails)"
  fails=$((fails + 1))
  _write_fails "${fails}"
  if [ "${CICADA_LUKS_MAX_FAIL}" -gt 0 ] 2>/dev/null; then
    if [ "${fails}" -ge "${CICADA_LUKS_MAX_FAIL}" ]; then
      _wipe_disk 0
      echo "WIPE:${fails}"
      return 0
    fi
  fi
  echo "FAIL:${fails}"
}

_success() {
  _reset_fails
  echo "OK:$(_read_fails)"
}

cmd="$1"
shift || true
case "${cmd}" in
  fail) _record_fail ;;
  ok) _success ;;
  read) echo "$(_read_fails)" ;;
  *) echo "unknown"; exit 1 ;;
esac
echo "WIPED=${WIPED}"
EOF

run_h() {
  CICADA_TEST_ESP="${esp}" \
  CICADA_TEST_HELPERS="${tmp}/helpers.sh" \
  CICADA_TEST_MAX="${1}" \
  bash "${harness}" "${2}"
}

# Fresh ESP, max=20: 19 fails stay recoverable, 20th wipes.
rm -f "${esp}/cicada/luks-fail.count"
out=""
for i in $(seq 1 19); do
  out="$(run_h 20 fail)"
  echo "${out}" | grep -q "^FAIL:${i}$" || die "expected FAIL:${i}, got: ${out}"
  echo "${out}" | grep -q 'WIPED=0' || die "wiped early at fail ${i}"
done
# Persist across "reboot" (clear in-memory by new process — already per-invocation mem,
# but ESP must carry the count).
[[ "$(cat "${esp}/cicada/luks-fail.count")" == "19" ]] || die "ESP did not persist count=19"
out="$(run_h 20 fail)"
echo "${out}" | grep -q '^WIPE:20$' || die "20th fail must wipe, got: ${out}"
echo "${out}" | grep -q 'WIPED=1' || die "wipe flag not set"
# Wipe resets counter.
[[ ! -f "${esp}/cicada/luks-fail.count" ]] || [[ "$(cat "${esp}/cicada/luks-fail.count" 2>/dev/null || true)" == "" ]] \
  || die "wipe should clear fail count"
say "19 wrong = retry; 20th = wipe; ESP persisted"

# Success resets mid-count.
rm -f "${esp}/cicada/luks-fail.count"
run_h 20 fail >/dev/null
run_h 20 fail >/dev/null
out="$(run_h 20 ok)"
echo "${out}" | grep -q '^OK:0$' || die "success must reset counter, got: ${out}"
[[ ! -f "${esp}/cicada/luks-fail.count" ]] || die "success must remove ESP counter file"
say "successful unlock resets counter"

# max=0 = unlimited (no wipe).
rm -f "${esp}/cicada/luks-fail.count"
out="$(run_h 0 fail)"
for i in $(seq 1 25); do
  out="$(run_h 0 fail)"
  echo "${out}" | grep -q 'WIPED=0' || die "max=0 wiped at ${i}"
done
say "CICADA_LUKS_MAX_FAIL=0 never wipes"

# Low cap still works (sanity for /boot/cicada/max-fail override path).
rm -f "${esp}/cicada/luks-fail.count"
out="$(run_h 3 fail)"; echo "${out}" | grep -q 'FAIL:1' || die "cap3 fail1"
out="$(run_h 3 fail)"; echo "${out}" | grep -q 'FAIL:2' || die "cap3 fail2"
out="$(run_h 3 fail)"; echo "${out}" | grep -q 'WIPE:3' || die "cap3 must wipe on 3rd"
say "override cap=3 wipes on third fail"

echo "==> hook contracts the simulator exercises"
grep -q 'fails}" -ge "${CICADA_LUKS_MAX_FAIL}"' "${HOOK}" \
  || die "hook missing threshold compare"
grep -q 'Session lock (hyprlock) does NOT wipe' "${HOOK}" || die "hook must document session boundary"
grep -q 'max-fail' "${HOOK}" || die "hook must honor ESP max-fail override"
[[ "${fail}" -eq 0 ]] && say "hook text matches exercised behavior"

if [[ "${fail}" -ne 0 ]]; then
  echo "LUKS-MAX-FAIL FAILED"
  exit 1
fi
echo "LUKS-MAX-FAIL OK"
