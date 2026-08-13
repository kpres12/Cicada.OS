#!/usr/bin/env bash
# Everything we can prove on the Mac without Hyprland, Wi-Fi, LUKS, or the Air.
# Run: tests/here.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

expect_exit() {
  local want="$1" desc="$2"
  shift 2
  local rc=0
  "$@" </dev/null >/dev/null 2>&1 || rc=$?
  if [[ "${rc}" -eq "${want}" ]]; then
    say "${desc} (exit ${want})"
  else
    die "${desc} (want ${want} got ${rc})"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/seal" "${tmp}/attest" "${tmp}/home"
export CICADA_SEAL_DIR="${tmp}/seal"
export CICADA_ATTEST_DIR="${tmp}/attest"
export HOME="${tmp}/home"
unset WAYLAND_DISPLAY DISPLAY || true

CICADA_BIN="${ROOT}/packages/cicada-defaults/files/usr/local/bin"
INSTALL_BIN="${ROOT}/packages/cicada-install/files/usr/local/bin"
RUN_BIN="${ROOT}/packages/cicada-run/files/usr/local/bin"
# Keep Homebrew/OpenSSL on PATH so seal tests can use ED25519. Isolate bwrap below.
export PATH="${CICADA_BIN}:${INSTALL_BIN}:${RUN_BIN}:${PATH}"

echo "==> Hyprland 0.56 config"
hypr="${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf"
grep -q 'dwindle:pseudotile' "${hypr}" && die "old dwindle:pseudotile" || true
grep -q 'misc:vfr' "${hypr}" && die "removed misc:vfr still present" || true
grep -Eq 'windowrule *= *float,' "${hypr}" && die "old windowrule float, title" || true
grep -q 'layoutmsg, togglesplit' "${hypr}" || die "missing layoutmsg togglesplit"
grep -q 'match:title' "${hypr}" || die "missing match: windowrules"
grep -q 'layout = dwindle' "${hypr}" || die "tiling not default"
grep -A2 'blur {' "${hypr}" | grep -q 'enabled = false' || die "blur not off"
grep -q 'cicada-firstboot' "${hypr}" && die "hyprland must not exec-once firstboot" || true
grep -q 'no_hardware_cursors = true' "${hypr}" || die "need software cursor on Intel"
say "hyprland 0.56 / tile / no blur"

echo "==> package policy"
pkgs="${ROOT}/iso/packages.cicada.x86_64"
grep -qx 'hardened_malloc' "${pkgs}" && die "AUR hardened_malloc in ISO list" || true
grep -qiE '^helium' "${pkgs}" && die "Helium on ISO" || true
grep -qx 'wlogout' "${pkgs}" && die "wlogout not in extra" || true
grep -qx 'openresolv' "${pkgs}" && die "openresolv (conflicts resolvconf)" || true
grep -qx 'cloud-init' "${pkgs}" && die "cloud-init in cicada extras" || true
grep -qx 'bubblewrap' "${pkgs}" || die "bubblewrap missing"
grep -qx 'xdg-dbus-proxy' "${pkgs}" || die "xdg-dbus-proxy missing"
grep -qx 'linux-hardened' "${pkgs}" || die "linux-hardened missing"
grep -qx 'cloud-init' "${ROOT}/iso/packages.exclude" || die "cloud-init not excluded"
say "official repos / excludes"

echo "==> scopes defaults"
hel="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.cicada.helium.env"
kp="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.keepassxc.KeePassXC.env"
grep -q '^NETWORK=allow' "${hel}" || die "Helium NETWORK must be allow"
grep -q '^CAMERA=deny' "${hel}" || die "Helium CAMERA deny"
grep -q '^NETWORK=deny' "${kp}" || die "KeePassXC NETWORK deny"
say "scopes (browser works, keepass net-off)"

echo "==> cicada-run is not bind-all"
grep -q -- '--bind / /' "${RUN_BIN}/cicada-run" && die "cicada-run still bind-mounts /" || true
grep -q -- '--ro-bind /usr /usr' "${RUN_BIN}/cicada-run" || die "no ro-bind /usr"
# Homebrew must not supply bwrap — this asserts fail-closed when it is missing.
expect_exit 78 "cicada-run without bwrap" \
  env PATH="/usr/bin:/bin" bash "${RUN_BIN}/cicada-run" org.cicada.helium -- /bin/true

echo "==> fail-closed CLIs"
bash "${INSTALL_BIN}/cicada-install" -h >/dev/null || die "install -h"
expect_exit 1 "install refuses non-root" bash "${INSTALL_BIN}/cicada-install" --target /dev/null
expect_exit 1 "duress-enroll as non-root" bash "${CICADA_BIN}/cicada-duress-enroll"
expect_exit 2 "tpm-enroll without TPM" bash "${CICADA_BIN}/cicada-tpm-enroll"
expect_exit 2 "sbctl-enroll without sbctl" bash "${CICADA_BIN}/cicada-sbctl-enroll"
expect_exit 1 "vpn on without wg0.conf" bash "${CICADA_BIN}/cicada-vpn" on
expect_exit 1 "auth refuses ungated action" bash "${CICADA_BIN}/cicada-auth" confirm wifi.connect
expect_exit 1 "auth refuses install with no TTY/UI" bash "${CICADA_BIN}/cicada-auth" confirm install
expect_exit 1 "backup without repo" env -u CICADA_BACKUP_REPO bash "${CICADA_BIN}/cicada-backup" backup
expect_exit 2 "beacon with no radio" bash "${CICADA_BIN}/cicada-beacon"
bash "${CICADA_BIN}/cicada-attest" >/dev/null
test -f "${tmp}/attest/README.txt" || die "attest missing README"
if openssl genpkey -algorithm ED25519 >/dev/null 2>&1; then
  if [[ -s "${tmp}/attest/device.pub" ]]; then
    say "attest wrote device.pub (no TPM path)"
  else
    die "attest did not write a non-empty device.pub"
  fi
else
  say "attest ran (openssl on this Mac has no ED25519; skip pubkey)"
fi

echo "==> install / malloc / lock policy in tree"
grep -q 'refusing Apple internal' "${INSTALL_BIN}/cicada-install" || die "install missing Apple refuse"
grep -q 'ld.so.preload' "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" || die "installed malloc preload missing"
grep -q '/run/archiso' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot" || die "firstboot must skip live malloc preload"
test ! -e "${ROOT}/iso/overlay/airootfs/etc/ld.so.preload" || die "overlay ships ld.so.preload"
grep -q 'CICADA_LOCK_REBOOT_SEC=1800' "${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env" || die "lock reboot not 30 min"
grep -q 'throw std::bad_alloc' "${ROOT}/scripts/build-hardened-malloc.sh" || die "malloc script missing GCC 16 patch"
grep -q 'x86-64-v3' "${ROOT}/scripts/build-hardened-malloc.sh" || die "malloc script missing ISO -march"
say "Apple refuse / malloc live-off / 30min reboot / gcc16 patch"

echo "==> privacy defaults"
nm="${ROOT}/packages/cicada-defaults/files/etc/NetworkManager/conf.d/cicada.conf"
grep -q 'enabled=false' "${nm}" || die "NM connectivity not off"
grep -q 'cloned-mac-address=random' "${nm}" || die "MAC random missing"
grep -q 'LLMNR=no' "${ROOT}/packages/cicada-defaults/files/etc/systemd/resolved.conf.d/cicada.conf" || die "LLMNR not off"
python3 - <<PY
import json, pathlib
p = pathlib.Path("${ROOT}/packages/cicada-defaults/files/etc/chromium/policies/managed/cicada.json")
d = json.loads(p.read_text())
assert d.get("MetricsReportingEnabled") is False
assert d.get("CloudReportingEnabled") is False
assert d.get("SyncDisabled") is True
assert d.get("DnsOverHttpsMode") == "off"
print("  OK  chromium managed telemetry/sync/DoH")
PY
grep -q 'kernel.kptr_restrict = 2' "${ROOT}/packages/cicada-defaults/files/etc/sysctl.d/99-cicada.conf" || die "kptr_restrict"
nft="${ROOT}/packages/cicada-defaults/files/etc/nftables.d/cicada-baseline.nft"
grep -q 'policy drop' "${nft}" || die "nft baseline not drop"
grep -q 'policy drop' "${ROOT}/packages/cicada-defaults/files/etc/cicada/killswitch.nft" || die "killswitch not drop"
say "NM / resolved / nft / sysctl"

echo "==> live overlay"
grep -q 'cicada:x:1000' "${ROOT}/iso/overlay/airootfs/etc/passwd" || die "live user"
grep -q '^cicada::' "${ROOT}/iso/overlay/airootfs/etc/shadow" || die "live empty password"
test -f "${ROOT}/docs/USER.md" || die "USER.md"

echo "==> wallpaper is PNG"
wall="${ROOT}/packages/cicada-shell/files/usr/share/cicada/wallpapers/cicada-3301.png"
if [[ -f "${wall}" ]]; then
  python3 - "${wall}" <<'PY'
import pathlib, sys
b = pathlib.Path(sys.argv[1]).read_bytes()[:8]
if b != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("not a PNG")
print("  OK  wallpaper PNG magic")
PY
else
  die "wallpaper missing"
fi

echo "==> duress hook tokens"
hook="${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt"
grep -q 'Invalid passphrase' "${hook}" || die "hook missing same error text"
grep -q 'luksErase' "${hook}" || die "hook missing luksErase"
grep -q 'CICADA_DURESS_BUDGET' "${hook}" || die "hook missing pad budget"
say "duress hook has pad + same error + erase"

echo "==> desktop launchers"
for f in web.desktop wifi.desktop files.desktop start-here.desktop; do
  test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/${f}" || die "missing ${f}"
done
grep -q '/usr/local/bin/chromium' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/web.desktop" || die "web.desktop not wrapped"
grep -q 'FIRST-BOOT.txt' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/start-here.desktop" || die "start-here"
say "desktop launchers"

echo "==> assemble profile (deep)"
export CICADA_PROFILE_DIR="${tmp}/profile"
bash "${ROOT}/iso/assemble-profile.sh" >/tmp/cicada-assemble.log 2>&1 || {
  tail -30 /tmp/cicada-assemble.log
  die "assemble"
}
P="${tmp}/profile"
test -f "${P}/airootfs/usr/share/cicada/FIRST-BOOT.txt" || die "FIRST-BOOT not in ISO tree"
grep -q 'Duress' "${P}/airootfs/usr/share/cicada/FIRST-BOOT.txt" || die "FIRST-BOOT missing Duress section"
test -L "${P}/airootfs/etc/systemd/system/sshd.service" || die "sshd not masked"
readlink "${P}/airootfs/etc/systemd/system/sshd.service" | grep -q '/dev/null' || die "sshd mask not /dev/null"
test -L "${P}/airootfs/etc/systemd/system/multi-user.target.wants/cicada-amnesic.service" || die "amnesic unit not enabled"
test -L "${P}/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service" || die "NM not enabled"
test ! -e "${P}/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" || die "networkd still enabled"
test -x "${P}/airootfs/usr/local/bin/chromium" || die "chromium wrapper not 755"
if [[ -e "${P}/airootfs/usr/local/bin/cicada-crypt" ]]; then
  die "cicada-crypt should be a hook not /usr/local/bin"
fi
test -f "${P}/airootfs/usr/lib/initcpio/hooks/cicada-crypt" || die "crypt hook not in airootfs"
test ! -e "${P}/airootfs/etc/ld.so.preload" || die "assembled live ships ld.so.preload"
test -f "${P}/airootfs/home/cicada/Desktop/start-here.desktop" || die "start-here not in live home"
grep -Rql copytoram "${P}/efiboot" || die "copytoram missing from UEFI entries"
grep -Rql 'lockdown=confidentiality' "${P}/efiboot" || die "hardened lockdown missing"
grep -Rql 'ibt=on' "${P}/efiboot" || die "CET cmdline missing"
amnesic=$(grep -l copytoram "${P}/efiboot/loader/entries/"*.conf 2>/dev/null | wc -l | tr -d ' ')
[[ "${amnesic}" -ge 1 ]] || die "no amnesic entry"
if grep -L copytoram "${P}/efiboot/loader/entries/"*.conf 2>/dev/null | grep -q .; then
  say "low-RAM live entry exists (no copytoram)"
else
  die "every boot entry is copytoram — 8GB Air will OOM"
fi
say "assemble deep checks"

echo "==> seal (again)"
bash "${ROOT}/tests/seal.sh" >/dev/null && say "seal chain+tamper"

if [[ "${fail}" -ne 0 ]]; then
  echo "HERE-TESTS FAILED"
  exit 1
fi
echo "HERE-TESTS OK"
