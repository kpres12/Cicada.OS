#!/usr/bin/env bash
# cicada-comms: the at-rest verdict, and the refusals.
#
# The interesting assertions here are the negative ones. A tool that says a
# message store is protected when it is not is worse than no tool, so most of
# this checks that cicada-comms declines to claim things: it refuses to bind
# into a profile that is only a directory, and it says out loud that unlinking a
# store on flash is not an erase.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ROOT}/packages/cicada-defaults/files/usr/local/bin"
COMMS="${BIN}/cicada-comms"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export HOME="${tmp}/home"
export CICADA_SEAL_DIR="${tmp}/seal"
export CICADA_PROFILE_ROOT="${HOME}/.local/share/cicada/profiles"
export CICADA_FLATPAK_ROOT="${HOME}/.var/app"
mkdir -p "${CICADA_SEAL_DIR}" "${CICADA_FLATPAK_ROOT}/org.signal.Signal/config/Signal"
# cicada-seal / cicada-auth must not be on PATH: shred is gated, and a test that
# pops a confirmation dialog is a test nobody runs twice.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

store="${CICADA_FLATPAK_ROOT}/org.signal.Signal/config/Signal"
echo '{"encryptedKey":"deadbeef"}' > "${store}/config.json"
: > "${store}/db.sqlite"

echo "==> status sees the store"
out="$(bash "${COMMS}" status 2>&1)" || die "status exited nonzero"
grep -q signal <<<"${out}" && say "signal is reported" || die "signal not reported: ${out}"
# No LUKS mapping named cicada on the test machine, so the honest verdict is the
# red one. Anything greener than this would be a lie.
grep -qE 'store in the real home|NOT on an encrypted volume' <<<"${out}" \
  && say "unbound store is not reported as protected" \
  || die "status over-claimed: ${out}"

echo "==> doctor explains itself"
out="$(bash "${COMMS}" doctor signal 2>&1)" || die "doctor exited nonzero"
grep -q 'safestorage\|safeStorage' <<<"${out}" \
  && say "doctor reads the key kind out of config.json" \
  || die "doctor missed the safeStorage key: ${out}"
grep -q 'secure element' <<<"${out}" \
  && say "doctor states the linked-desktop limit" \
  || die "doctor omitted the linked-desktop note"

echo "==> bind refuses a profile that only looks encrypted"
mkdir -p "${CICADA_PROFILE_ROOT}/chat/home"
rc=0
out="$(bash "${COMMS}" bind signal chat 2>&1)" || rc=$?
if [[ "${rc}" -ne 0 ]] && grep -q 'plain directory' <<<"${out}"; then
  say "bind into a non-encrypted profile is refused"
else
  die "bind accepted a plain directory profile (rc=${rc})"
fi
[[ -d "${store}" && ! -L "${store}" ]] \
  && say "refused bind left the store where it was" \
  || die "refused bind moved the store anyway"

rc=0
bash "${COMMS}" bind signal nosuch >/dev/null 2>&1 || rc=$?
[[ "${rc}" -ne 0 ]] && say "bind to a missing profile is refused" || die "bind invented a profile"

echo "==> unbind on an unbound store is refused"
rc=0
bash "${COMMS}" unbind signal >/dev/null 2>&1 || rc=$?
[[ "${rc}" -ne 0 ]] && say "unbind refuses when nothing is bound" || die "unbind claimed success"

echo "==> shred says what it could not guarantee"
rc=0
out="$(bash "${COMMS}" shred signal --duress 2>&1)" || rc=$?
[[ "${rc}" -eq 0 ]] || die "shred --duress exited ${rc}"
grep -q 'not an erase' <<<"${out}" \
  && say "unlink is not reported as an erase" \
  || die "shred over-claimed: ${out}"
[[ ! -d "${store}" ]] && say "store is gone" || die "store survived shred"

echo "==> scopes match the tools"
for id in org.signal.Signal chat.simplex.simplex im.riot.Riot; do
  sys="${ROOT}/packages/cicada-shell/files/usr/share/cicada/scopes/${id}.env"
  skel="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/${id}.env"
  [[ -f "${sys}" ]] || die "missing system floor for ${id}"
  [[ -f "${skel}" ]] || die "missing skel scope for ${id}"
  cmp -s "${sys}" "${skel}" || die "skel scope for ${id} drifted from the system floor"
  grep -q '^CAMERA=deny' "${sys}" || die "${id} floor grants the camera"
  grep -q '^MIC=deny' "${sys}" || die "${id} floor grants the microphone"
  grep -q '^FILES=portal' "${sys}" || die "${id} floor is not FILES=portal"
  # cicada-run must bind a store for every scope that persists one, or the app
  # gets a tmpfs home and silently loses its history every launch.
  grep -q "${id})" "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" \
    || die "cicada-run has no bind block for ${id}"
done
say "three messenger scopes, floors and skel in agreement"

# Electron is Chromium: with the PID namespace unshared the zygote cannot fork.
grep -q 'org.signal.Signal|im.riot.Riot) UNSHARE_PID=0' \
  "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" \
  && say "Electron messengers are exempt from --unshare-pid" \
  || die "Signal/Element will come up as a blank window (--unshare-pid)"

echo "==> permission floors apply to apps that are NOT on the curated list"
# The curated list is curation; the floors are containment. Once there is an
# escape hatch, an unlisted app must still land under the floors — and
# apply_flatpak_overrides used to `return 0` for anything it did not recognise,
# which would have given every escape-hatch install zero confinement.
helper="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-pkg-helper"
python3 - "${helper}" <<'PY' || die "unlisted Flatpaks would be installed with no floors"
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
body = t[t.index("apply_flatpak_overrides() {"):t.index("is_permission_tool()")]
if re.search(r'flatpak_row "\$\{app_id\}"\)"\s*\|\|\s*return', body):
    print("  apply_flatpak_overrides still bails out for unlisted apps"); sys.exit(1)
for need in ("--nofilesystem=home", "--nosocket=x11", "--nodevice=all"):
    seg = body[:body.index("if [[ -n \"${extra}")] if 'if [[ -n "${extra}' in body else body
    if need not in seg:
        print(f"  {need} is not applied unconditionally"); sys.exit(1)
sys.exit(0)
PY
say "unlisted apps still get home denied / no X11 / no standing device access"

grep -q 'flatpak-install-any' "${helper}" || die "no escape hatch: GUI apps capped at the curated list"
grep -q 'is_permission_tool' "${helper}" || die "nothing stops a permission-rewriting app undoing the floors"
say "escape hatch exists, and permission-rewriting apps are still refused"

echo "==> the Flatpak floors cannot be lifted by the user"
# Measured, not assumed: user overrides are merged after system ones and win.
# With a real app installed, `flatpak info --show-permissions` goes from
# "filesystems=" back to "filesystems=home;" after a single
# `flatpak override --user --filesystem=home`. Without the lock below, every
# floor on every graphical app is one command away from gone — including for
# anything running as the user, not just the user.
lock="${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/lock-flatpak-overrides.sh"
test -x "${lock}" || die "nothing stops a user override lifting the Flatpak floors"
grep -q 'repo\|app' "${lock}" || die "lock must refuse to clobber an existing per-user installation"
# An empty root-owned directory sits in a user-writable parent and can simply be
# removed and replaced; it needs root-owned content to survive. Tested both ways.
grep -q 'cicada-managed' "${lock}" || die "lock leaves an empty dir the user can delete and replace"
grep -q 'lock-flatpak-overrides' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot" \
  || die "lock never runs at boot, so profiles created later are unprotected"
grep -q 'lock-flatpak-overrides' "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" \
  || die "lock never runs at install, so the first user is unprotected until a reboot"
grep -q 'lock-flatpak-overrides' "${ROOT}/iso/assemble-profile.sh" || die "lock not registered for the ISO"
# And the comment that used to claim system overrides win must not come back.
grep -q 'user override can grant back what a user override removed' \
  "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-pkg-helper" \
  && die "the false claim that system floors survive a user override is back" || true
say "floors are locked at install and every boot; the false 'system wins' claim is gone"

echo "==> shred is a gated action"
grep -q 'comms.shred' "${BIN}/cicada-auth" \
  && say "cicada-auth gates comms.shred" \
  || die "comms.shred is not in the cicada-auth gate list"

[[ "${fail}" -eq 0 ]] || { echo "COMMS TESTS FAILED"; exit 1; }
echo "comms ok"
