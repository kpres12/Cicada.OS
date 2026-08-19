#!/usr/bin/env bash
# The AFU controls, simulated: USB gate, gate restore, watchdog arming.
#
# These three sat on the README's known-unverified list because they need a
# Linux machine with real hardware. Most of what was unverified about them is
# not the hardware, though — it is the decision logic wrapped around it, and
# that runs anywhere. This builds fake hub and watchdog trees and checks the
# verdict, in the spirit of tests/seccomp.sh rather than tests/here.sh.
#
# What this still does NOT prove: that a chipset watchdog resets an Intel Air,
# or that the kernel refuses a real USB device at authorized_default=0. Those
# need the machine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ROOT}/packages/cicada-defaults/files/usr/local/bin"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# --- USB gate ---------------------------------------------------------------
echo "==> USB gate writes every hub"
sysfs="${tmp}/usbsys"
mkdir -p "${sysfs}/usb1" "${sysfs}/usb2" "${sysfs}/notahub"
echo 1 > "${sysfs}/usb1/authorized_default"
echo 1 > "${sysfs}/usb2/authorized_default"
echo 1 > "${sysfs}/notahub/authorized_default"

# EUID 0 is required by the script and we are not root, so drive the loop with
# a shim that skips only that check. Everything else is the real script.
gate() {
  CICADA_USB_SYSFS="${sysfs}" bash -c '
    sed "s/^\[\[ \${EUID} -eq 0 \]\].*$//" "$1" > "$2/gate.sh"
    bash "$2/gate.sh" "$3"
  ' _ "${BIN}/cicada-usb-gate" "${tmp}" "$1"
}

gate 0 >/dev/null 2>&1 || die "gate 0 exited nonzero on a writable tree"
[[ "$(cat "${sysfs}/usb1/authorized_default")" == 0 ]] || die "usb1 not closed"
[[ "$(cat "${sysfs}/usb2/authorized_default")" == 0 ]] || die "usb2 not closed"
say "closing the gate writes 0 to every usb* hub"
# The glob is usb*, so a sibling directory that is not a host controller must be
# left alone — otherwise the gate is writing to things it does not understand.
[[ "$(cat "${sysfs}/notahub/authorized_default")" == 1 ]] \
  && say "non-hub directories are untouched" \
  || die "gate wrote to a directory that is not a usb* hub"

gate 1 >/dev/null 2>&1 || die "gate 1 exited nonzero"
[[ "$(cat "${sysfs}/usb1/authorized_default")" == 1 ]] || die "usb1 not restored"
say "restoring the gate writes 1 back"

echo "==> a gate that could not write does not report success"
# This is the regression that mattered: the old version redirected writes to
# /dev/null and exited 0 unconditionally, so a gate that closed nothing looked
# exactly like one that closed everything.
chmod 444 "${sysfs}/usb1/authorized_default"
rc=0
out="$(gate 0 2>&1)" || rc=$?
if [[ "${rc}" -ne 0 ]] && grep -q 'could not write' <<<"${out}"; then
  say "an unwritable hub is a nonzero exit and a message, not silence"
else
  die "unwritable hub still reported success (rc=${rc})"
fi
chmod 644 "${sysfs}/usb1/authorized_default"

echo "==> no hubs at all is reported, not silently 'protected'"
empty="${tmp}/emptysys"; mkdir -p "${empty}"
rc=0
out="$(CICADA_USB_SYSFS="${empty}" bash -c '
  sed "s/^\[\[ \${EUID} -eq 0 \]\].*$//" "$1" > "$2/gate2.sh"
  bash "$2/gate2.sh" 0' _ "${BIN}/cicada-usb-gate" "${tmp}" 2>&1)" || rc=$?
grep -q 'no USB host controllers' <<<"${out}" \
  && say "an empty tree says so out loud" \
  || die "empty tree was silent: ${out}"

# --- the restore path -------------------------------------------------------
echo "==> cicada-lock restores the gate on abnormal exit, not just on unlock"
# The bug: without an EXIT trap, killing cicada-lock leaves authorized_default
# at 0 with no process left that will ever set it back, and no USB device can be
# authorized until reboot.
grep -q 'trap _restore_usb EXIT' "${BIN}/cicada-lock" \
  && say "an EXIT trap owns the restore" \
  || die "cicada-lock has no EXIT trap — a killed lock strands the USB gate closed"
# ...but it must NOT restore while the screen is genuinely still locked.
grep -A2 '_restore_usb() {' "${BIN}/cicada-lock" | grep -q 'pidof hyprlock' \
  && say "the trap declines to open the gate while hyprlock still holds the screen" \
  || die "the trap would open the USB gate on a still-locked screen"

# --- watchdog ---------------------------------------------------------------
echo "==> watchdog refuses to arm when it cannot learn the real timeout"
# The failure mode of this daemon is "reboots your machine", so uncertainty has
# to mean do nothing. /dev/null is a character device and writable, which is
# enough to get past the device checks and reach the timeout logic.
rc=0
out="$(CICADA_WATCHDOG_DEV=/dev/null CICADA_WATCHDOG_SYSFS="${tmp}/nowd" \
       bash "${BIN}/cicada-watchdog" 2>&1)" || rc=$?
if [[ "${rc}" -eq 2 ]] && grep -q 'refusing to arm' <<<"${out}"; then
  say "unreadable hardware timeout => refuses to arm (exit 2)"
else
  die "watchdog armed without knowing the timeout (rc=${rc}): ${out}"
fi

echo "==> watchdog derives the pet interval from the driver, not the request"
wdsys="${tmp}/wdsys/watchdog0"; mkdir -p "${wdsys}"
# Ask for 30, have the "driver" report 12: a driver that clamps below the pet
# interval is how a healthy machine reboots at random.
echo 12 > "${wdsys}/timeout"
out="$(CICADA_WATCHDOG_DEV=/dev/null CICADA_WATCHDOG_SYSFS="${tmp}/wdsys" \
       CICADA_WATCHDOG_TIMEOUT=30 CICADA_WATCHDOG_CHECK=1 \
       bash "${BIN}/cicada-watchdog" 2>&1)" || true
[[ "${out}" == *"timeout=12"* ]] \
  && say "uses the driver's timeout (12), not the requested 30" \
  || die "did not read back the driver timeout: ${out}"
[[ "${out}" == *"pet=4"* ]] \
  && say "pets at a third of the real timeout (4s)" \
  || die "wrong pet interval: ${out}"

# Floor: a 3-second driver timeout must not produce a 1-second pet.
echo 3 > "${wdsys}/timeout"
out="$(CICADA_WATCHDOG_DEV=/dev/null CICADA_WATCHDOG_SYSFS="${tmp}/wdsys" \
       CICADA_WATCHDOG_CHECK=1 bash "${BIN}/cicada-watchdog" 2>&1)" || true
[[ "${out}" == *"pet=2"* ]] \
  && say "pet interval floors at 2s on a very short timeout" \
  || die "pet floor not applied: ${out}"

echo "==> cicada.nomalloc rescues a machine that is already broken"
# The bug: the hatch only *declined to add* the preload, and it sat below the
# firstboot marker check that exits on every boot after the first. Since
# hardened_malloc is enabled after install by cicada-malloc, the boot where
# someone needs the rescue always has the marker — so the documented escape
# hatch could never fire on a machine that needed it.
fbdir="${tmp}/fb"; mkdir -p "${fbdir}"

# Run the real script with two substitutions and nothing else: drop the root
# check (we are not root), and point the firstboot marker at our tmpdir so the
# script exits cleanly right after the block under test. Both are stated here
# rather than hidden in a pipeline, because a test harness that is hard to read
# is a test nobody trusts when it fails.
sed -e 's/\${EUID} -eq 0/0 -eq 0/g' \
    -e "s|^MARKER=.*|MARKER=${fbdir}/marker|" \
    "${BIN}/cicada-firstboot" > "${fbdir}/fb.sh"
touch "${fbdir}/marker"          # the state that made this unreachable before

run_fb() {
  CICADA_CMDLINE="${fbdir}/cmdline" CICADA_PRELOAD="${fbdir}/preload" \
    bash "${fbdir}/fb.sh" >/dev/null 2>&1 || true
}

echo "BOOT_IMAGE=/vmlinuz root=/dev/sda2 rw cicada.nomalloc" > "${fbdir}/cmdline"
echo "/usr/lib/libhardened_malloc.so" > "${fbdir}/preload"
run_fb
if [[ ! -s "${fbdir}/preload" ]] || ! grep -q libhardened_malloc "${fbdir}/preload" 2>/dev/null; then
  say "cicada.nomalloc removes an existing preload even after the firstboot marker"
else
  die "cicada.nomalloc left the preload in place — the documented rescue does nothing"
fi

echo "==> the hatch preserves unrelated preloads"
printf '/usr/lib/libsomethingelse.so\n/usr/lib/libhardened_malloc.so\n' > "${fbdir}/preload"
run_fb
if grep -q libsomethingelse "${fbdir}/preload" 2>/dev/null \
   && ! grep -q libhardened_malloc "${fbdir}/preload" 2>/dev/null; then
  say "an unrelated preload survives the rescue"
else
  die "rescue clobbered a preload that was not hardened_malloc"
fi

echo "==> without the flag, the rescue does not fire"
# The hatch must not be a permanent disable: booting normally has to leave an
# intentional preload alone.
echo "BOOT_IMAGE=/vmlinuz root=/dev/sda2 rw" > "${fbdir}/cmdline"
echo "/usr/lib/libhardened_malloc.so" > "${fbdir}/preload"
run_fb
grep -q libhardened_malloc "${fbdir}/preload" 2>/dev/null \
  && say "a normal boot leaves the preload intact" \
  || die "the rescue fired without cicada.nomalloc on the cmdline"

echo "==> watchdog hatch"
grep -q 'cicada.nowatchdog' "${BIN}/cicada-watchdog" \
  && say "cicada-watchdog honours cicada.nowatchdog (source check; cmdline not fakeable here)" \
  || die "cicada-watchdog has no cicada.nowatchdog escape hatch"

[[ "${fail}" -eq 0 ]] || { echo "AFU TESTS FAILED"; exit 1; }
echo "afu ok"
