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
grep -A1 'animations {' "${hypr}" | grep -q 'enabled = false' || die "animations must be off (input lag)"
grep -q 'fullscreen on' "${hypr}" && die "desktop must not be fullscreen over the dock" || true
grep -q 'style=default' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/wofi/config" && die "wofi style=default ignores Cicada CSS" || true
grep -q 'QuickExec=true' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/pcmanfm-qt/default/settings.conf" || die "desktop icons will prompt Open vs Execute"
grep -q SETTINGS "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" || die "waybar missing SETTINGS"
grep -q 'bind = $mainMod, M, exit' "${hypr}" && die "Super+M must not kill the session" || true
grep -q 'WLR_NO_HARDWARE_CURSORS' "${ROOT}/packages/cicada-shell/files/etc/skel/.bash_profile" && die "software cursors lag HD 6000" || true
grep -q 'WLR_NO_HARDWARE_CURSORS' "${ROOT}/iso/overlay/airootfs/home/cicada/.bash_profile" && die "overlay bash_profile still forces software cursors" || true
grep -q 'lock_cmd = pidof hyprlock || cicada-lock' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hypridle.conf" || die "hypridle must lock via cicada-lock"
grep -q 'nofocus on' "${hypr}" && die "pcmanfm nofocus makes desktop icons unclickable" || true
grep -q 'bind = $mainMod, T, exec, kitty' "${hypr}" || die "Super+T should open terminal"
grep -q 'hyprctl keyword general:gaps_out' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-dock" || die "dock move must update Hyprland gaps"
grep -q 'custom/rf' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" && die "dead waybar custom/rf still defined" || true
grep -q '%H:%M}Z' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" && die "waybar clock still appends Z to local time" || true
grep -q 'cicada-settings brightness' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" || die "BRI click must open brightness, not full settings"
grep -q 'cicada-settings sound' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" || die "VOL click must open Cicada sound, not pavucontrol"
grep -q 'exec, pcmanfm-qt' "${hypr}" || die "Super+E must open pcmanfm-qt"
grep -q 'exec pavucontrol' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" && die "settings still dumps into pavucontrol" || true
grep -q 'exec nwg-look' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" && die "settings still dumps into nwg-look" || true
grep -q 'exec wdisplays' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" && die "settings still dumps into wdisplays" || true
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
grep -qx 'network-manager-applet' "${pkgs}" && die "nm-applet opens the connection editor" || true
grep -qx 'thunar' "${pkgs}" && die "Thunar still in ISO extras (pcmanfm-qt is Files)" || true
grep -qx 'pavucontrol' "${pkgs}" && die "pavucontrol still in ISO extras" || true
grep -qx 'nwg-look' "${pkgs}" && die "nwg-look still in ISO extras" || true
grep -qx 'wdisplays' "${pkgs}" && die "wdisplays still in ISO extras" || true
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
# broadcom-wl cannot be driven by iwd and cannot randomize scan MACs. Both
# settings look like "no networks found" on the MBA.
grep -q 'wifi.backend=wpa_supplicant' "${nm}" || die "NM backend must be wpa_supplicant for broadcom-wl"
grep -q 'wifi.scan-rand-mac-address=no' "${nm}" || die "scan MAC rand breaks broadcom-wl scanning"
mb="${ROOT}/packages/cicada-defaults/files/etc/modprobe.d/cicada-blacklist.conf"
grep -q '^blacklist bcma' "${mb}" || die "bcma may steal BCM4360 from wl"
grep -q '^blacklist brcmfmac' "${mb}" && die "brcmfmac needed for BCM43602 Airs" || true
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

echo "==> anti-forensic defaults (LinuxLEO artifact classes)"
hist="${ROOT}/packages/cicada-defaults/files/etc/profile.d/cicada-history.sh"
grep -q 'HISTFILE=/dev/null' "${hist}" || die "shell history still lands on disk"
grep -q 'SAVEHIST=0' "${hist}" || die "zsh SAVEHIST not zeroed"
jd="${ROOT}/packages/cicada-defaults/files/etc/systemd/journald.conf.d/cicada.conf"
grep -q '^Storage=volatile' "${jd}" || die "journal persists to /var/log/journal"
grep -q '^ForwardToSyslog=no' "${jd}" || die "journal forwarded to a second sink"
gtk="${ROOT}/packages/cicada-shell/files/etc/skel/.config/gtk-3.0/settings.ini"
grep -q 'gtk-recent-files-max-age=0' "${gtk}" || die "recently-used.xbel still recorded"
tf="${ROOT}/packages/cicada-defaults/files/etc/tmpfiles.d/cicada.conf"
grep -q 'thumbnails' "${tf}" || die "thumbnail cache not wiped at boot"
grep -q 'recently-used.xbel' "${tf}" || die "recent-files list not wiped at boot"
inst="${INSTALL_BIN}/cicada-install"
grep -q 'subvol=@,noatime' "${inst}" || die "installed root mounts with atime"
grep -q 'subvol=@home,noatime' "${inst}" || die "installed home mounts with atime"
grep -q 'umask=0077' "${inst}" || die "ESP world-readable"
say "history off / journal volatile / no recent+thumbs / noatime / ESP 0077"
nft="${ROOT}/packages/cicada-defaults/files/etc/nftables.d/cicada-baseline.nft"
grep -q 'policy drop' "${nft}" || die "nft baseline not drop"
grep -q 'policy drop' "${ROOT}/packages/cicada-defaults/files/etc/cicada/killswitch.nft" || die "killswitch not drop"
# The output chain must NOT exempt established flows: that lets pre-tunnel
# connections keep running on wlan0, and lets flows fail over to the physical
# interface when wg0 dies. Parse the chain rather than grepping the whole file,
# since the input chain legitimately keeps the rule.
python3 - <<PY || die "killswitch output chain exempts established flows (leak)"
import pathlib, re, sys
t = pathlib.Path("${ROOT}/packages/cicada-defaults/files/etc/cicada/killswitch.nft").read_text()
m = re.search(r"chain output \{(.*?)\n  \}", t, re.S)
if not m:
    sys.exit("no output chain found")
body = "\n".join(l for l in m.group(1).splitlines() if not l.strip().startswith("#"))
sys.exit(1 if "ct state established" in body else 0)
PY
grep -q 'killswitch failed to load' "${CICADA_BIN}/cicada-vpn" || die "cicada-vpn fails open if nft errors"
grep -q 'wg-quick down wg0' "${CICADA_BIN}/cicada-vpn" || die "cicada-vpn does not tear down on killswitch failure"
grep -q 'trap cleanup EXIT' "${RUN_BIN}/cicada-run" || die "cicada-run leaks xdg-dbus-proxy on nonzero app exit"

echo "==> lock cannot strand a passwordless session"
lock="${CICADA_BIN}/cicada-lock"
grep -q 'live-nopasswd' "${lock}" || die "cicada-lock will lock a session with no password"
grep -q 'passwd -S' "${lock}" || die "cicada-lock lacks a live no-password check"
grep -q 'live-nopasswd' "${CICADA_BIN}/cicada-firstboot" || die "firstboot does not publish the no-password marker"
# The live user ships passwordless on purpose; that is exactly why lock must refuse.
grep -q '^cicada::' "${ROOT}/iso/overlay/airootfs/etc/shadow" || die "live user no longer passwordless (revisit lock guard)"
# Not executed here: cicada-lock's success path runs hyprlock, which would grab
# this machine's display. Structure is asserted statically instead.
grep -q -- '--force' "${lock}" || die "no deliberate-lock escape hatch"
say "lock guard present (marker + passwd -S + --force escape)"
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
for f in web.desktop wifi.desktop files.desktop start-here.desktop term.desktop settings.desktop; do
  test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/${f}" || die "missing ${f}"
done
grep -q '/usr/local/bin/chromium' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/web.desktop" || die "web.desktop not wrapped"
grep -q 'Exec=pcmanfm-qt' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/files.desktop" || die "Files must be pcmanfm-qt"
grep -q 'inode/directory=pcmanfm-qt.desktop' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/mimeapps.list" || die "directories must open in pcmanfm-qt"
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
test ! -e "${P}/airootfs/etc/systemd/system/multi-user.target.wants/usbguard.service" || die "usbguard enabled on live"
test ! -e "${P}/airootfs/etc/systemd/system/multi-user.target.wants/apparmor.service" || die "apparmor enabled on live"
test ! -e "${P}/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" || die "networkd still enabled"
grep -q Hyprland "${P}/airootfs/home/cicada/.bash_profile" || die "live home does not start Hyprland"
grep -q 'cicada-firstboot' "${P}/airootfs/home/cicada/.config/hypr/hyprland.conf" && die "assembled hypr still exec-once firstboot" || true
def=$(echo "${P}/efiboot/loader/entries/"01-*.conf)
grep -q intel_iommu "${def}" && die "default live entry has intel_iommu (breaks Apple iGPU)" || true
test ! -f "${P}/efiboot/loader/entries/00-cicada-amnesic.conf" || die "amnesic must not be 00- (sorts first)"
test -f "${P}/efiboot/loader/entries/04-cicada-amnesic.conf" || die "amnesic entry 04 missing"
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

echo "==> amnesic verify"
CICADA_PROFILE_DIR="${P}" bash "${ROOT}/tests/amnesic-verify.sh" || die "amnesic-verify"

echo "==> seal (again)"
bash "${ROOT}/tests/seal.sh" >/dev/null && say "seal chain+tamper"

if [[ "${fail}" -ne 0 ]]; then
  echo "HERE-TESTS FAILED"
  exit 1
fi
echo "HERE-TESTS OK"
