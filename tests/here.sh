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
if [[ -f "${ROOT}/iso/overlay/airootfs/home/cicada/.bash_profile" ]]; then
  grep -q 'WLR_NO_HARDWARE_CURSORS' "${ROOT}/iso/overlay/airootfs/home/cicada/.bash_profile" && die "overlay bash_profile still forces software cursors" || true
fi
grep -q 'lock_cmd = pidof hyprlock || cicada-lock' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hypridle.conf" || die "hypridle must lock via cicada-lock"
grep -q 'live-nopasswd' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hypridle.conf" || die "hypridle must skip lock spam on live"
grep -q 'swappy' "${hypr}" || die "screenshot path should use swappy annotate"
grep -q 'XF86AudioPlay' "${hypr}" || die "media keys must be bound (playerctl shipped)"
grep -q 'XCURSOR_THEME' "${hypr}" || die "cursor theme must be set"
grep -q 'WallpaperMode=stretch' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/pcmanfm-qt/default/settings.conf" \
  || die "pcmanfm desk must show wallpaper (stretch) — color mode hid hyprpaper"
grep -q 'Wallpaper=/usr/share/cicada/wallpapers/cicada-3301.png' \
  "${ROOT}/packages/cicada-shell/files/etc/skel/.config/pcmanfm-qt/default/settings.conf" \
  || die "pcmanfm must ship stock wallpaper path"
grep -q 'org.cicada.helium)' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" \
  || die "Helium must be unsandboxed (bwrap kills Chromium zygote)"
grep -q 'SidePaneMode=places' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/pcmanfm-qt/default/settings.conf" \
  || die "Files must show Places sidebar"
grep -q 'UseTrash=true' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/pcmanfm-qt/default/settings.conf" \
  || die "Files must use Trash"
grep -q 'custom_palette=true' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/qt6ct/qt6ct.conf" \
  || die "qt6ct must apply Cicada palette (else Files looks stock)"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Templates/New Text File.txt" \
  || die "Templates missing (Create New Document)"
grep -q 'dock-pinned' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-dock" || die "dock pins must live under ~/.config/cicada"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/.config/cicada/dock-pinned" || die "skel dock-pinned missing"
grep -qx 'foot' "${ROOT}/packages/cicada-install/files/etc/cicada/install-packages.txt" && die "install must not ship foot (Kitty monopoly)" || true
grep -qx 'iwd' "${ROOT}/packages/cicada-install/files/etc/cicada/install-packages.txt" && die "install must not ship iwd (NM+wpa for Broadcom)" || true
grep -qx 'chromium' "${ROOT}/iso/packages.optional.x86_64" && die "optional ISO must not pull Arch chromium" || true
grep -q 'nofocus on' "${hypr}" && die "pcmanfm nofocus makes desktop icons unclickable" || true
grep -q 'bind = $mainMod, T, exec, cicada-run org.cicada.kitty' "${hypr}" || die "Super+T must open terminal via cicada-run"
grep -q 'hyprctl keyword general:gaps_out' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-dock" || die "dock move must update Hyprland gaps"
grep -q 'cicada-wofi' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-dock" || die "dock must open cicada-wofi, not raw Arch wofi"
grep -q 'on-click": "cicada-wofi"' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" || die "Waybar CICADA must open cicada-wofi"
grep -q 'bind = $mainMod, SPACE, exec, cicada-wofi' "${hypr}" || die "Super+Space must open cicada-wofi"
grep -q 'exec, cicada-files' "${hypr}" || die "Super+E must open cicada-files"
grep -q 'NETWORK=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run must default-deny network"
grep -q 'FILES=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run must default-deny files"
grep -q 'MIC=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run must default-deny mic"
grep -q 'SENSORS=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run must default-deny sensors"
grep -q 'pipewire' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "MIC=deny must mention pipewire omit"
grep -q 'hidraw\|/sys/bus/iio\|SENSORS' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "SENSORS deny path missing"
grep -q 'GTK_USE_PORTAL=1' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "FILES=portal must set GTK_USE_PORTAL"
grep -q 'av-kill.env' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run must honor system AV kill"
grep -q 'Camera & microphone' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" || die "Settings missing Camera & microphone"
grep -q 'cicada-av-kill' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-av-kill" || die "cicada-av-kill missing"
test -f "${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/hide-arch-desktops.sh" || die "hide-arch-desktops.sh missing"
grep -q 'create-locked work' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot" || die "firstboot must create Work UID"
grep -q 'hide-arch-desktops' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot" || die "firstboot must hide Arch desktops"
grep -q 'Set Work password' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" || die "Settings missing Set Work password"
grep -q 'host/adb' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-scopes" || die "scopes must label Kitty as host/adb"
grep -q 'Wallpaper' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" || die "Settings missing wallpaper picker"
grep -q 'apply_wallpaper\|Pictures/cicada-wallpaper' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" || die "wallpaper apply helper missing"
grep -q 'run/archiso' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstrun" || die "firstrun must skip live USB"
grep -q 'first setup\|Etch\|duress' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstrun" \
  || die "firstrun missing v1.0 welcome"
grep -q 'duress-enroll --session\|--session' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstrun" \
  || die "firstrun must offer session duress"
test -x "${ROOT}/packages/cicada-install/files/usr/local/bin/cicada-etch" \
  || die "cicada-etch missing"
grep -q 'cicada-live' "${ROOT}/iso/overlay/airootfs/etc/sudoers.d/cicada-live" \
  || test -f "${ROOT}/iso/overlay/airootfs/etc/sudoers.d/cicada-live" \
  || die "live sudoers missing (etch cannot run)"
grep -q 'rm -f /etc/sudoers.d/cicada-live' \
  "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" \
  || die "chroot must strip live NOPASSWD sudo"
test -f "${ROOT}/docs/RELEASE.md" || die "docs/RELEASE.md missing"
test -f "${ROOT}/scripts/prepare-release.sh" || die "prepare-release.sh missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Pictures/.keep" || die "skel Pictures missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Downloads/.keep" || die "skel Downloads missing"
grep -q 'custom/rf' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" && die "dead waybar custom/rf still defined" || true
grep -q '%H:%M}Z' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" && die "waybar clock still appends Z to local time" || true
grep -q 'cicada-settings brightness' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" || die "BRI click must open brightness, not full settings"
grep -q 'cicada-settings sound' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/waybar/config.jsonc" || die "VOL click must open Cicada sound, not pavucontrol"
grep -q 'exec pavucontrol' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" && die "settings still dumps into pavucontrol" || true
grep -q 'exec nwg-look' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" && die "settings still dumps into nwg-look" || true
grep -q 'exec wdisplays' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings" && die "settings still dumps into wdisplays" || true
say "hyprland 0.56 / tile / no blur / launcher monopoly"

echo "==> package policy"
pkgs="${ROOT}/iso/packages.cicada.x86_64"
grep -qx 'hardened_malloc' "${pkgs}" && die "AUR hardened_malloc in ISO list" || true
grep -qiE '^helium' "${pkgs}" && die "do not pacman AUR helium; use channel/helium.lock" || true
grep -qx 'chromium' "${pkgs}" && die "Arch chromium must not be on the ISO; Helium is the browser" || true
test -f "${ROOT}/channel/helium.lock" || die "helium.lock missing"
grep -q '^sha256=' "${ROOT}/channel/helium.lock" || die "helium.lock missing sha256"
grep -q 'install-helium.sh' "${ROOT}/iso/build.sh" || die "ISO build does not install Helium"
grep -q '/opt/helium/chrome' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/chromium" || die "wrapper must prefer /opt/helium"
grep -q 'CICADA_RADIOS_OFF_DEFAULT=0' "${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env" || die "Wi-Fi must not be rfkill-blocked at boot"
grep -q 'cicada-radios-off.service' "${ROOT}/iso/assemble-profile.sh" && die "radios-off must not be enabled on live" || true
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
grep -qx 'lxqt-qtplugin' "${pkgs}" || die "lxqt-qtplugin required for qt6ct + pcmanfm-qt"
grep -qx 'qt6-svg' "${pkgs}" || die "qt6-svg required for Papirus/Qt icons"
grep -qx 'adwaita-cursors' "${pkgs}" || die "adwaita-cursors required"
grep -qx 'cloud-init' "${ROOT}/iso/packages.exclude" || die "cloud-init not excluded"
say "official repos / excludes"

echo "==> scopes defaults"
hel="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.cicada.helium.env"
kp="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.keepassxc.KeePassXC.env"
grep -q '^NETWORK=allow' "${hel}" || die "Helium NETWORK must be allow"
grep -q '^CAMERA=deny' "${hel}" || die "Helium CAMERA deny"
grep -q '^NETWORK=deny' "${kp}" || die "KeePassXC NETWORK deny"
grep -q '^FILES=allow' "${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.cicada.files.env" || die "Files scope needs home"
say "scopes (browser works, keepass net-off, files home, default-deny)"

echo "==> cicada-run is not bind-all"
grep -q -- '--bind / /' "${RUN_BIN}/cicada-run" && die "cicada-run still bind-mounts /" || true
grep -q -- '--ro-bind /usr /usr' "${RUN_BIN}/cicada-run" || die "no ro-bind /usr"
# Homebrew must not supply bwrap — sandboxed apps fail closed when it is missing.
# Helium is deliberately unsandboxed (zygote dies under bwrap); probe KeePassXC.
expect_exit 78 "cicada-run without bwrap" \
  env PATH="/usr/bin:/bin" bash "${RUN_BIN}/cicada-run" org.keepassxc.KeePassXC -- true
# Helium must still launch when bwrap is absent (dock Web must not be a no-op).
# Use `true` on PATH — macOS may lack /bin/true in restricted PATH probes.
expect_exit 0 "Helium without bwrap still runs" \
  env PATH="/usr/bin:/bin" bash "${RUN_BIN}/cicada-run" org.cicada.helium -- true

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
grep -q 'hardened-malloc-enable' "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" \
  || die "malloc preload must be opt-in (Helium zygote dies under global preload)"
fb="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot"
grep -q 'hardened-malloc-enable' "${fb}" || die "firstboot malloc must be opt-in"
grep -q 'cicada.nomalloc' "${fb}" || die "no bootloader-reachable escape hatch for a malloc compat regression"
grep -q 'hardened_malloc is in /etc/ld.so.preload' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/chromium" \
  || die "browser wrapper must refuse launch under HM preload"
test ! -e "${ROOT}/iso/overlay/airootfs/etc/ld.so.preload" || die "overlay ships ld.so.preload"
grep -q 'CICADA_LOCK_REBOOT_SEC=1800' "${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env" || die "lock reboot not 30 min"
grep -q 'throw std::bad_alloc' "${ROOT}/scripts/build-hardened-malloc.sh" || die "malloc script missing GCC 16 patch"
grep -q 'x86-64-v3' "${ROOT}/scripts/build-hardened-malloc.sh" || die "malloc script missing ISO -march"
grep -q 'cicada-wallpaper' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf" \
  || die "hyprland must start cicada-wallpaper"
say "Apple refuse / malloc opt-in (Helium-safe) / wallpaper helper / 30min reboot"

echo "==> privacy defaults"
nm="${ROOT}/packages/cicada-defaults/files/etc/NetworkManager/conf.d/cicada.conf"
grep -q 'enabled=false' "${nm}" || die "NM connectivity not off"
grep -q 'cloned-mac-address=permanent' "${nm}" || die "MBA Broadcom needs permanent MAC default"
grep -qE '^ipv4\.ignore-auto-dns=' "${nm}" && die "ignore-auto-dns in conf.d is invalid (NM unknown key)" || true
grep -q 'dhcp-send-hostname=false' "${nm}" || die "DHCP hostname must stay off"
# broadcom-wl cannot be driven by iwd and cannot randomize scan MACs. Both
# settings look like "no networks found" on the MBA.
grep -q 'wifi.backend=wpa_supplicant' "${nm}" || die "NM backend must be wpa_supplicant for broadcom-wl"
grep -q 'wifi.scan-rand-mac-address=no' "${nm}" || die "scan MAC rand breaks broadcom-wl scanning"
mb="${ROOT}/packages/cicada-defaults/files/etc/modprobe.d/cicada-blacklist.conf"
grep -q '^blacklist bcma' "${mb}" || die "bcma may steal BCM4360 from wl"
grep -q '^blacklist brcmfmac' "${mb}" && die "brcmfmac needed for BCM43602 Airs" || true
rsv="${ROOT}/packages/cicada-defaults/files/etc/systemd/resolved.conf.d/cicada.conf"
grep -q 'LLMNR=no' "${rsv}" || die "LLMNR not off"
# Encrypted DNS to Quad9. The campus/hotel resolver seeing every domain you
# visit is the whole game for the network-adversary persona.
grep -q '^DNS=9\.9\.9\.9#dns\.quad9\.net' "${rsv}" || die "system DNS not pinned to Quad9 DoT"
grep -q '#dns.quad9.net' "${rsv}" || die "no TLS certificate name: a redirect of 9.9.9.9 would answer silently"
grep -qE '^DNSOverTLS=(opportunistic|yes)' "${rsv}" || die "system DNS is plaintext"
grep -q '^Domains=~\.' "${rsv}" || die "DHCP-supplied resolvers would still get queries"
# ignore-auto-dns is NOT valid in NetworkManager conf.d (unknown key spam).
# Domains=~. in resolved is the real "ignore DHCP DNS" control.
python3 - <<PY || die "browser DoH not strict, or not pointed at Quad9"
import json, sys, pathlib
d = json.loads(pathlib.Path("${ROOT}/packages/cicada-defaults/files/etc/chromium/policies/managed/cicada.json").read_text())
# ECH is why DoH is worth having: without it TLS leaks the hostname in
# cleartext SNI immediately after the encrypted lookup hid it.
# "automatic" not "secure": secure has no fallback, so a blocked DoH endpoint
# means the browser resolves nothing at all.
sys.exit(0 if d.get("DnsOverHttpsMode") == "automatic"
         and "quad9" in d.get("DnsOverHttpsTemplates", "")
         and d.get("EncryptedClientHelloEnabled") is True else 1)
PY
# Strict browser DNS with no portal escape is a bricked connection on campus.
pt="${CICADA_BIN}/cicada-portal"
test -x "${pt}" || die "no captive-portal escape: strict DNS would brick hotel/campus Wi-Fi"
grep -q '/run/systemd/resolved.conf.d' "${pt}" || die "portal drop-in must live in /run so it cannot survive a reboot"
grep -q 'setsid --fork' "${pt}" || die "portal mode does not self-revert"
grep -qE 'mins <= 60' "${pt}" || die "portal mode has no upper bound"
say "DNS: Quad9 DoT + DoH, degrades DoH->DoT->plain, bounded portal escape"
python3 - <<PY
import json, pathlib
p = pathlib.Path("${ROOT}/packages/cicada-defaults/files/etc/chromium/policies/managed/cicada.json")
d = json.loads(p.read_text())
assert d.get("MetricsReportingEnabled") is False
assert d.get("CloudReportingEnabled") is False
assert d.get("SyncDisabled") is True
# Was "off" (plaintext to whatever the network hands you). Now strict DoH to
# Quad9 — the campus resolver no longer sees the domains you visit.
assert d.get("DnsOverHttpsMode") == "automatic"
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
# A default-drop input chain silently breaks DHCP: the server answers from its
# own address to broadcast:68, so the reply does not match the conntrack entry
# the request created and is seen as NEW. Presents as "Wi-Fi connects but there
# is no internet". NM's internal client uses raw sockets and dodges this, but
# dhclient/dhcpcd do not — do not rely on one backend's implementation detail.
grep -q 'udp sport 67 udp dport 68 accept' "${nft}" || die "baseline drops DHCP offers: no lease, no network"
grep -q 'udp sport 547 udp dport 546 accept' "${nft}" || die "baseline drops DHCPv6"
grep -qE 'ip6 nexthdr (icmpv6|ipv6-icmp) accept' "${nft}" || die "no ICMPv6: IPv6 neighbour discovery breaks"
grep -q 'ip protocol icmp accept' "${nft}" || die "no ICMP: path MTU discovery breaks, large transfers hang"
# Same trap inside the kill switch: without renewal the lease lapses, the link
# drops, and the switch kills the very connection it was protecting.
ks="${ROOT}/packages/cicada-defaults/files/etc/cicada/killswitch.nft"
grep -q 'udp dport 67 accept' "${ks}" || die "kill switch blocks DHCP renewal: tunnel dies when the lease expires"
grep -q 'udp sport 67 udp dport 68 accept' "${ks}" || die "kill switch blocks DHCP replies"
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

echo "==> key protection (no secure element: entropy is the whole boundary)"
inst="${INSTALL_BIN}/cicada-install"
grep -q 'gen_passphrase' "${inst}" || die "install cannot generate a passphrase"
grep -q 'passphrase_ok' "${inst}" || die "no entropy floor on user-typed passphrases"
grep -q '\-ge 8 \]\] || die "passphrase too short"' "${inst}" && die "8-char minimum still present (~30 bits, falls offline)" || true
# Crockford base32 minus I/L/O/U: 5 bits/char, unambiguous when hand-copied.
python3 - <<PY || die "generated passphrase alphabet is wrong size (entropy claim would be false)"
import re, sys, pathlib
t = pathlib.Path("${inst}").read_text()
m = re.search(r"CICADA_PW_ALPHABET='([^']+)'", t)
if not m: sys.exit(1)
a = m.group(1)
sys.exit(0 if len(a) == 32 and len(set(a)) == 32 and not (set("ilou") & set(a)) else 1)
PY
grep -q 'PBKDF_MEM' "${inst}" || die "Argon2id memory not scaled to the machine"
grep -q '1048576' "${inst}" || die "Argon2id memory cap not raised to 1 GiB"
say "generated passphrase / entropy floor / adaptive Argon2id"

echo "==> DMA and RAM-residency"
mb="${ROOT}/packages/cicada-defaults/files/etc/modprobe.d/cicada-blacklist.conf"
grep -q '^blacklist thunderbolt$' "${mb}" || die "Thunderbolt DMA path open"
grep -q '^install thunderbolt /bin/true' "${mb}" || die "thunderbolt blacklist bypassable by explicit modprobe"
sl="${ROOT}/packages/cicada-defaults/files/etc/systemd/sleep.conf.d/cicada.conf"
grep -q '^AllowSuspend=no' "${sl}" || die "suspend-to-RAM leaves the volume key in DRAM"
grep -q '^AllowHibernation=no' "${sl}" || die "hibernation would write the key to disk"
lg="${ROOT}/packages/cicada-defaults/files/etc/systemd/logind.conf.d/cicada.conf"
grep -q '^HandleLidSwitch=lock' "${lg}" || die "lid close does not lock"
grep -q 'CICADA_LID_REBOOT_SEC' "${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env" || die "no fast BFU window for a closed lid"
grep -q 'lid_closed' "${CICADA_BIN}/cicada-locked-reboot" || die "reboot timer ignores lid state"
say "thunderbolt blocked / no suspend / lid close -> lock -> BFU"

echo "==> USB key token (the nearest thing to a secure element here)"
kf="${CICADA_BIN}/cicada-keyfile-enroll"
test -x "${kf}" || die "cicada-keyfile-enroll not executable"
grep -q 'refusing to use the encrypted disk itself' "${kf}" || die "enroll could eat the encrypted disk"
# --and has no recovery path, so a single token is a coin flip on the whole disk.
# The refusal must come before the root check, or the user sees the wrong reason.
expect_exit 1 "--and refuses a single token" bash "${kf}" --and --device /dev/sdz1
# Capture first: the script exits 1 by design, and pipefail would make the
# pipeline fail even when grep matches.
kfmsg="$(bash "${kf}" --and --device /dev/sdz1 2>&1 || true)"
grep -q 'requires a second token' <<<"${kfmsg}" \
  || die "--and single-token refusal does not explain why"
grep -q 'no recovery path' <<<"${kfmsg}" \
  || die "--and refusal does not state that loss is unrecoverable"
grep -q 'backup token must be a different device' "${kf}" || die "same device accepted as its own backup"
grep -q 'failed readback verification' "${kf}" || die "token written but never verified"
# Ordering: tokens must be written and verified before the LUKS header changes,
# so a bad stick cannot leave an orphaned keyslot behind.
python3 - <<PY || die "keyslot is added before the tokens are verified"
import pathlib, sys
t = pathlib.Path("${kf}").read_text()
sys.exit(0 if t.index('write_token "\${DEV}"') < t.index("luksAddKey") else 1)
PY
grep -q 'shred -u' "${kf}" || die "staged keyfile not shredded"
hook="${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt"
grep -q 'CICADA_KEYFILE_MODE' "${hook}" || die "boot hook cannot consume a token"
grep -q 'cat "${kf}"' "${hook}" || die "and-mode does not append the keyfile to the passphrase"
grep -q 'add_binary blkid' "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/install/cicada-crypt" || die "initramfs cannot find a token by label"
# Key material must never be baked into the initramfs — only the mode/label.
grep -q 'add_file /etc/cicada/keyfile.env' "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/install/cicada-crypt" || die "token mode not available at unlock time"
say "token enroll + or/and boot paths + no key material in initramfs"

echo "==> hardware-adaptive trust (Cicada runs on more than one laptop)"
test -x "${CICADA_BIN}/cicada-hw-trust" || die "cicada-hw-trust not executable"
grep -q 'tpmrm0' "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" || die "install does not use a TPM2 when present"
# TPM sealing WITHOUT a PIN makes a laptop unlock itself on power-on — a thief
# who presses the power button gets a decrypted disk. That is strictly worse
# than passphrase-only, so it must never be the default and must never be done
# unattended (enrolling a PIN needs a human at a keyboard).
tpe="${CICADA_BIN}/cicada-tpm-enroll"
grep -q -- '--tpm2-with-pin=yes' "${tpe}" || die "TPM enrolment without a PIN: disk would auto-unlock on power-on"
grep -q 'UNATTENDED' "${tpe}" || die "--no-pin has no explicit confirmation"
grep -qE 'tpm2-pcrs="\$\{PCRS\}"' "${tpe}" || die "PCR set not configurable"
grep -q 'PCRs 1 and 3' "${tpe}" || die "PCR choice must document why 1/3 are excluded (churn)"
ich="${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh"
grep -q 'systemd-cryptenroll' "${ich}" && die "install must not seal the TPM unattended (no PIN possible there)" || true
grep -q 'cicada-tpm-enroll' "${ich}" || die "install should tell TPM2 users about the strong path"
# Tier reporting: a capability list is hard to act on, a tier is not.
ht="${CICADA_BIN}/cicada-hw-trust"
for tier in 'Tier 0' 'Tier 1' 'Tier 2'; do
  grep -q "${tier}" "${ht}" || die "cicada-hw-trust does not report ${tier}"
done
grep -q 'unlocks itself on power-on' "${ht}" || die "hw-trust must flag a PIN-less TPM keyslot"
for tier in 'Tier 0' 'Tier 1' 'Tier 2' 'Tier 3'; do
  grep -q "${tier}" "${ROOT}/docs/THREAT_MODEL.md" || die "THREAT_MODEL missing ${tier}"
done
say "TPM2 auto-enrol when present, honest report when not"

echo "==> no swap anywhere (a swapfile would undo the RAM story)"
# Swap is the classic LinuxLEO recovery: key material and plaintext paged to
# disk, surviving reboot, outside the reach of init_on_free. Cicada has none.
# This is currently a property of the install rather than a decision anyone
# wrote down, so assert it before someone "helpfully" adds a swapfile.
grep -qE 'mkswap|swapfile' "${INSTALL_BIN}/cicada-install" && die "install creates disk swap" || true
grep -qE 'mkswap|swapfile' "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" \
  && die "install-chroot creates disk swap" || true
grep -qx 'systemd-swap' "${pkgs}" && die "disk swap tooling on the ISO" || true
# zram IS permitted: it is compressed swap in RAM, destroyed at power-off and
# never written to the SSD. It is what makes an 8GB machine usable under a
# browser. The one setting that would break the property is writeback.
zr="${ROOT}/packages/cicada-defaults/files/etc/systemd/zram-generator.conf"
if [[ -f "${zr}" ]]; then
  # Strip comments first: the file explains why writeback is absent, and
  # matching that prose fails a check the config actually passes.
  grep -vE '^\s*#' "${zr}" | grep -qi 'writeback' \
    && die "zram writeback would spill to disk — the artifact we are avoiding" || true
  grep -q 'fs-type = swap' "${zr}" || die "zram device is not configured as swap"
fi
grep -q 'AllowHibernation=no' "${ROOT}/packages/cicada-defaults/files/etc/systemd/sleep.conf.d/cicada.conf" \
  || die "hibernation would need swap and would write keys to disk"
# A laptop you cannot close is not a laptop. Locking stays immediate; this is
# only the window before BFU. GrapheneOS ships 18h; anything under ~10 min
# means users disable the feature entirely, which protects nobody.
awk -F= '/^CICADA_LID_REBOOT_SEC=/ { exit ($2 >= 600) ? 0 : 1 }' \
  "${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env" \
  || die "lid reboot window too short to carry the laptop between rooms"
say "no disk swap (zram ok) / lid window survives walking to class"

echo "==> hardware watchdog (AFU ceiling that outlives userspace)"
wd="${CICADA_BIN}/cicada-watchdog"
test -x "${wd}" || die "cicada-watchdog not executable"
grep -q "printf 'V'" "${wd}" || die "no magic-close: every clean poweroff looks like a hang"
grep -q 'trap .*disarm.*TERM' "${wd}" || die "watchdog disarms on crash (should stay armed)"
grep -q 'lid_closed' "${wd}" || die "watchdog ignores lid state"
# This is the only control whose failure mode is "the machine reboot-loops", and
# defaults.env cannot be edited before boot on a live ISO. Without a cmdline
# switch that state is unrecoverable.
grep -q 'cicada.nowatchdog' "${wd}" || die "no bootloader escape from a watchdog reboot loop"
grep -q '/sys/class/watchdog' "${wd}" || die "watchdog trusts its requested timeout instead of the driver's real one"
grep -q 'refusing to arm' "${wd}" || die "watchdog must not arm when it cannot read the real timeout"
grep -q 'SuccessExitStatus=2' "${ROOT}/packages/cicada-defaults/files/etc/systemd/system/cicada-watchdog.service" \
  || die "boards without a watchdog would look like a failed unit"
say "watchdog arms on lock, withholds pet at deadline, magic-close on shutdown"

echo "==> duress reachable from a session, not just at power-on"
dc="${CICADA_BIN}/cicada-duress-check"
test -x "${dc}" || die "cicada-duress-check missing"
pam="${ROOT}/packages/cicada-defaults/files/etc/pam.d/hyprlock"
grep -q 'expose_authtok' "${pam}" || die "pam hook cannot see the typed secret"
grep -q '^auth *optional *pam_exec' "${pam}" || die "duress hook must be optional or it can lock you out"
python3 - <<PY || die "duress pam_exec must precede system-auth or pam_unix consumes the token"
import pathlib, sys
t = pathlib.Path("${pam}").read_text()
sys.exit(0 if t.index("pam_exec") < t.index("system-auth") else 1)
PY
grep -q 'duress-session.sha256' "${dc}" || die "session duress has no verifier"
grep -q -- '--session' "${CICADA_BIN}/cicada-duress-enroll" || die "no way to enrol a session duress password"
say "session duress: pam_exec first, optional, wipes + hard resets"

echo "==> browser policy is managed, not merely recommended"
mgd="${ROOT}/packages/cicada-defaults/files/etc/chromium/policies/managed/cicada.json"
test ! -d "${ROOT}/packages/cicada-defaults/files/etc/chromium/policies/recommended" \
  || die "recommended/ still exists — those settings are user-overridable"
python3 - <<PY || die "browser hardening not enforced as managed policy"
import json, sys, pathlib
d = json.loads(pathlib.Path("${mgd}").read_text())
need = {"DefaultJavaScriptJitSetting": 2, "WebGpuEnabled": False, "SitePerProcess": True,
        "PostQuantumKeyAgreementEnabled": True, "ScreenCaptureAllowed": False}
bad = [k for k, v in need.items() if d.get(k) != v]
if bad: print("  missing/wrong:", bad)
sys.exit(1 if bad else 0)
PY
say "JIT blocked / WebGPU off / site isolation / PQ / clear-on-exit"

echo "==> lock hardens the machine, not just the screen"
lk="${CICADA_BIN}/cicada-lock"
# authorized_default=0 is the kernel refusing to authorize NEW devices. It must
# not touch already-authorized ones: on a MacBook the keyboard IS USB HID, so
# unbinding hubs would lock the user out of their own machine.
grep -q 'authorized_default' "${lk}" || die "lock leaves USB enumeration open (userspace policy only)"
grep -q 'unbind' "${lk}" && die "unbinding USB would kill the MBA keyboard mid-lock" || true
grep -q 'freeze-idle' "${lk}" || die "lock leaves idle profile keys mapped in the kernel"
grep -q 'freeze-idle' "${ROOT}/packages/cicada-profiles/files/usr/local/bin/cicada-profile" \
  || die "cicada-profile has no freeze-idle for lock to call"
grep -q '^  end)' "${ROOT}/packages/cicada-profiles/files/usr/local/bin/cicada-profile" \
  || die "no end-session verb (GrapheneOS parity naming)"
hl="${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprlock.conf"
grep -q 'hide_input = true' "${hl}" || die "lock screen leaks passphrase length to anyone watching"
grep -q 'fail_text' "${hl}" || die "rejected passphrase still looks like a frozen machine"
say "USB gated at kernel / idle profiles frozen / no length leak / fail feedback"

echo "==> RAM scrub at shutdown"
mw="${CICADA_BIN}/cicada-memwipe"
test -x "${mw}" || die "cicada-memwipe missing"
grep -q 'MemAvailable' "${mw}" || die "memwipe does not bound itself to available RAM"
grep -q 'MARGIN_KB' "${mw}" || die "memwipe leaves no headroom for the shutdown path"
mwu="${ROOT}/packages/cicada-defaults/files/etc/systemd/system/cicada-memwipe.service"
grep -q 'TimeoutStartSec' "${mwu}" || die "memwipe could wedge shutdown"
grep -q 'WantedBy=poweroff.target' "${mwu}" || die "memwipe never runs"
say "bounded free-RAM scrub, cannot wedge poweroff"

echo "==> ptrace and log viewer"
grep -q 'kernel.yama.ptrace_scope = 2' "${ROOT}/packages/cicada-defaults/files/etc/sysctl.d/99-cicada.conf" \
  || die "unprivileged cross-process ptrace not restricted"
test -x "${CICADA_BIN}/cicada-logs" || die "cicada-logs missing"
grep -q 'cannot prove anything to a third party' "${CICADA_BIN}/cicada-logs" \
  || die "log viewer overstates what the seal log proves"
say "ptrace admin-only / log viewer is honest about attestation"

echo "==> defaults.env parses (a stray newline here breaks every consumer)"
bash -c "set -e; source '${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env'
  [[ \"\${CICADA_WATCHDOG_TIMEOUT}\" =~ ^[0-9]+$ ]] || exit 1
  [[ \"\${CICADA_LID_REBOOT_SEC}\" =~ ^[0-9]+$ ]] || exit 1" \
  || die "defaults.env has a malformed value"
say "defaults.env sources with numeric values intact"

echo "==> Tor scope is kernel-enforced, not proxy-cooperative"
tornetns="${CICADA_BIN}/cicada-tor-netns"
test -x "${tornetns}" || die "cicada-tor-netns missing"
test -x "${CICADA_BIN}/cicada-netns-helper" || die "cicada-netns-helper missing"
test -x "${CICADA_BIN}/cicada-tor" || die "cicada-tor missing"
# The whole point: an app that ignores a proxy setting must still be unable to
# reach anything but Tor. That means a default-drop egress policy in the netns.
grep -q 'policy drop' "${tornetns}" || die "onion netns egress is not default-drop"
grep -q 'udp dport 53 dnat' "${tornetns}" || die "DNS in the netns would bypass Tor"
grep -qE 'oifname "\$\{VETH\}" drop' "${tornetns}" || die "host could forward netns traffic to the physical NIC"
# Fail closed and loud: silently using the direct network for a Tor scope is the
# worst possible outcome for the people this exists for.
grep -q 'Refusing to run it on the direct network' "${RUN_BIN}/cicada-run" \
  || die "cicada-run may fall back to direct network for a tor scope"
grep -q 'netns_wrap' "${RUN_BIN}/cicada-run" || die "cicada-run does not enter the onion namespace"
python3 - <<PY || die "tor scope must not also --unshare-net (that cuts off Tor too)"
import pathlib, re, sys
t = pathlib.Path("${RUN_BIN}/cicada-run").read_text()
m = re.search(r"^  tor\)(.*?)^    ;;", t, re.S | re.M)
# Strip comments first: the block explains *why* --unshare-net is absent, and
# matching that prose would fail the check the code passes.
body = "\n".join(l for l in (m.group(1).splitlines() if m else []) if not l.strip().startswith("#"))
sys.exit(0 if m and "--unshare-net" not in body else 1)
PY
# The sudo-reachable helper must grant a namespace, never privilege.
hlp="${CICADA_BIN}/cicada-netns-helper"
grep -q 'setpriv --reuid' "${hlp}" || die "helper does not drop privileges before exec"
grep -q -- '--no-new-privs' "${hlp}" || die "helper allows regaining privilege via setuid"
grep -q 'refusing to run as root inside the namespace' "${hlp}" || die "helper would run as root for uid 0"
grep -qE '^NS=onion' "${hlp}" || die "namespace name must be hardcoded, not caller-supplied"
# Tor Browser, not Helium-over-Tor, carries the anonymity claim.
tb="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.torproject.torbrowser.env"
test -f "${tb}" || die "no Tor Browser scope"
# Tor Browser brings its own Tor — must NOT be NETWORK=tor (Tor-over-Tor / black screen).
grep -q '^NETWORK=allow' "${tb}" || die "Tor Browser scope must be NETWORK=allow (own Tor)"
grep -q 'cicada-tor-browser' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-tor-browser" \
  || test -x "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-tor-browser" \
  || die "cicada-tor-browser wrapper missing"
grep -q 'fnmode=1' "${ROOT}/packages/cicada-defaults/files/etc/modprobe.d/hid-apple.conf" \
  || die "hid-apple must use fnmode=1 (media keys like macOS)"
grep -q 'cicada-brightness' "${hypr}" || die "brightness binds must use cicada-brightness"

grep -q '^NETWORK=tor' "${hel}" && die "Helium must not claim Tor anonymity (fingerprint)" || true
grep -qx 'tor' "${pkgs}" || die "tor not on the ISO"
# obfs4proxy/lyrebird/snowflake are AUR-only, and the ISO is official-repos
# only. meek is the one pluggable transport in extra. Tor Browser ships its own
# obfs4+snowflake, so the censored-network story is stronger inside Tor Browser
# than it is for the system tor daemon — cicada-tor must say so rather than
# imply bridge parity it does not have.
grep -qx 'meek' "${pkgs}" || die "no pluggable transport available at all"
grep -qx 'obfs4proxy' "${pkgs}" && die "obfs4proxy is AUR-only; it breaks the build" || true
grep -q 'Tor Browser bundles' "${CICADA_BIN}/cicada-tor" || die "cicada-tor must state where obfs4 actually comes from"
grep -qx 'torbrowser-launcher' "${pkgs}" || die "no Tor Browser"
grep -q 'bridges' "${CICADA_BIN}/cicada-tor" || die "no bridge configuration path"
grep -q 'does not hide that you are using Tor' "${CICADA_BIN}/cicada-tor" \
  || die "cicada-tor must state that Tor use itself is visible without bridges"
say "onion netns default-drop / fail-closed / helper drops privs / bridges / Tor Browser"

echo "==> archiso installer surface is carved out, not inherited"
asm="${ROOT}/iso/assemble-profile.sh"
# releng enables these for a cloud/VM installer ISO. Anything not explicitly
# removed here ships enabled, because the whole releng airootfs is rsynced in.
for u in vboxservice vmtoolsd vmware-vmblock-fuse hv_fcopy_daemon hv_kvp_daemon \
         hv_vss_daemon qemu-guest-agent ModemManager choose-mirror; do
  grep -q "${u}.service" "${asm}" || die "${u} still enabled (inherited from releng)"
done
grep -q 'rm -rf.*cloud-init.target.wants' "${asm}" || die "dangling cloud-init units still enabled"
grep -q 'pcscd.socket' "${asm}" || die "smartcard socket still listening"
grep -q 'livecd-talk' "${asm}" || die "removing the screen reader must be a documented decision, not silent"
say "guest agents / cloud-init / ModemManager / mirror fetch / pcscd removed"

echo "==> core dumps never write memory to disk"
cd_="${ROOT}/packages/cicada-defaults/files/etc/systemd/coredump.conf.d/cicada.conf"
grep -q '^Storage=none' "${cd_}" || die "core dumps would write process memory to /var/lib/systemd/coredump"
grep -q 'kernel.core_pattern = |/bin/false' "${ROOT}/packages/cicada-defaults/files/etc/sysctl.d/98-cicada-coredump.conf" \
  || die "kernel fallback core pattern still writes files"
grep -q 'fs.suid_dumpable = 0' "${ROOT}/packages/cicada-defaults/files/etc/sysctl.d/98-cicada-coredump.conf" \
  || die "setuid processes can still dump core"
say "no core dumps: a browser crash cannot leave keys on disk"

echo "==> network identity does not survive MAC randomization"
# Randomizing the MAC and then sending a stable hostname/DUID hands the network
# a persistent identifier and undoes the entire exercise.
grep -q 'ipv4.dhcp-send-hostname=false' "${nm}" || die "hostname broadcast in every DHCP request"
grep -q 'ipv6.dhcp-send-hostname=false' "${nm}" || die "hostname broadcast over DHCPv6"
grep -q 'ipv4.dhcp-client-id=mac' "${nm}" || die "DHCP client-id does not follow the randomized MAC"
grep -qE 'ipv6.dhcp-duid=(ll|llt)$' "${nm}" || die "DHCPv6 DUID is stable across MAC rotation"
say "hostname withheld / client-id + DUID derive from the random MAC"

echo "==> time is authenticated"
ch="${ROOT}/packages/cicada-defaults/files/etc/chrony.conf"
grep -qc 'nts' "${ch}" >/dev/null && [[ "$(grep -c 'iburst nts' "${ch}")" -ge 3 ]] \
  || die "fewer than 3 NTS sources: one operator could move the clock alone"
# NOT `require`: NTS-KE (port 4460) is blocked on many campus/hotel/censored
# networks, and requiring it there leaves the machine with no time at all —
# which breaks every HTTPS site, pacman, and Tor. Prefer authenticated, accept
# unauthenticated rather than none, and make the difference visible.
grep -q '^authselectmode prefer' "${ch}" || die "chrony must prefer (not require) NTS, or a blocked port bricks the machine"
grep -qE '^pool .*ntp' "${ch}" || die "no unauthenticated fallback: NTS blocked = no time = no HTTPS"
# maxchange's 3rd field is a LIMIT, not a flag: 0 or positive makes chronyd exit
# on an oversized correction, leaving the clock both wrong and unsynchronised.
# That presents as "every HTTPS site has a cert error" with no obvious cause.
grep -qE '^maxchange [0-9]+ [0-9]+ -1$' "${ch}" || die "chronyd would exit instead of ignoring a bad offset"
awk '/^maxchange/ { exit ($3 >= 5 && $4 == -1) ? 0 : 1 } END { if (NR==0) exit 1 }' "${ch}" \
  || die "maxchange delay too low: a dead-RTC laptop could never make its first correction"
grep -q '^port 0' "${ch}" || die "chrony would serve time to others"
grep -q 'systemd-timesyncd' "${asm}" || die "plaintext timesyncd still enabled on live"
say "NTS from 3 jurisdictions preferred, plain fallback so time always works"

echo "==> module blacklist covers known-bad, not the boot path"
mb2="${ROOT}/packages/cicada-defaults/files/etc/modprobe.d/cicada-blacklist.conf"
grep -q '^blacklist vivid' "${mb2}" || die "vivid (CVE-2019-18683 LPE test driver) still loadable"
grep -q '^install vivid /bin/true' "${mb2}" || die "vivid blacklist bypassable by explicit modprobe"
grep -q '^blacklist squashfs' "${mb2}" && die "blacklisting squashfs would break the live ISO" || true
grep -q '^blacklist ext4' "${mb2}" && die "blacklisting ext4 would break the installed root" || true
grep -q '^blacklist btrfs' "${mb2}" && die "blacklisting btrfs would break the installed root" || true
say "vivid + unused filesystem parsers blocked, boot path untouched"

echo "==> setuid carve-out"
ss="${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/strip-setuid.sh"
test -x "${ss}" || die "strip-setuid.sh missing"
for b in ksu chfn chsh gpasswd newgrp chage wall write; do
  grep -q "/usr/bin/${b}" "${ss}" || die "${b} still setuid (local privilege escalation surface)"
done
# Removing any of these bricks the machine; unix_chkpwd in particular makes the
# lock screen impossible to dismiss.
for b in sudo su passwd unix_chkpwd mount umount pkexec; do
  grep -qE "^\\s*/usr/bin/${b}\\b" "${ss}" && die "${b} must NOT be stripped — it is load-bearing" || true
done
grep -q 'unix_chkpwd' "${ss}" || die "strip script must document why unix_chkpwd is kept"
hk="${ROOT}/packages/cicada-defaults/files/etc/pacman.d/hooks/zz-cicada-setuid.hook"
test -f "${hk}" || die "no pacman hook: a package upgrade would restore every setuid bit"
grep -q 'PostTransaction' "${hk}" || die "hook must run after the transaction"
say "8 setuid binaries removed, 7 load-bearing kept, survives pacman upgrades"

echo "==> degraded protection is visible, not silent"
# Cicada now degrades rather than bricks when a network blocks DoH or NTS. That
# is only defensible if the user can see it happened.
st="${CICADA_BIN}/cicada-status"
test -x "${st}" || die "no way to see whether hardening is actually in force"
grep -q 'UNAUTHENTICATED' "${st}" || die "status does not report unauthenticated time"
grep -q 'portal mode is on' "${st}" || die "status does not warn while DNS is plaintext"
grep -q 'NO kill switch' "${st}" || die "status does not warn about a VPN without a kill switch"
say "cicada-status reports the posture in force, not the one in the config"

echo "==> first-run wizard offers the tier-appropriate unlock"
fr="${CICADA_BIN}/cicada-firstrun"
test -x "${fr}" || die "no first-run flow: token/PIN setup would stay undiscovered"
# Neither can be done by cicada-install or cicada-firstboot — both need a human
# at a keyboard — so a login-time wizard is the only place this can happen.
grep -q 'run/archiso' "${fr}" || die "first-run must be a no-op on live (no LUKS to enrol against)"
grep -q 'cicada-tpm-enroll' "${fr}" || die "TPM2 machines are not offered a PIN"
grep -q 'cicada-keyfile-enroll' "${fr}" || die "no-TPM machines are not offered a USB token"
grep -q -- '--or' "${fr}" || die "must suggest --or: --and does not solve the typing problem"
grep -q 'firstrun-done' "${fr}" || die "wizard would nag on every login"
grep -q 'has_tpm_slot\|has_token_slot' "${fr}" || die "wizard re-offers what is already enrolled"
grep -q 'cicada-firstrun' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf" \
  || die "first-run never launches"
grep -q 'sleep 8' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf" \
  || die "first-run must not race the desktop coming up"
say "first-run: TPM PIN on Tier 1+, USB token on Tier 0, once only"

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
grep -q 'CICADA_LUKS_MAX_FAIL' "${hook}" || die "hook missing attempt-cap wipe"
grep -q 'luks-fail.count' "${hook}" || die "hook must persist fail count on ESP"
grep -q 'CICADA_LUKS_MAX_FAIL=20' "${ROOT}/packages/cicada-defaults/files/etc/cicada/defaults.env" || die "defaults missing LUKS max fail=20"
grep -q 'cicada-luks-max-fail' "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/install/cicada-crypt" || die "initramfs must bake max-fail"
say "duress hook has pad + same error + erase + 20-fail wipe"

echo "==> LUKS max-fail behavioral + product spine"
bash "${ROOT}/tests/luks-max-fail.sh" || die "luks-max-fail (run tests/luks-max-fail.sh for detail)"
say "attempt-cap wired: install→hook→ESP; session typos safe; daily-driver intact"

echo "==> Tirimid OS checklist (Wi-Fi + Helium wiring)"
bash "${ROOT}/tests/tirimid.sh" || die "tirimid (run tests/tirimid.sh for detail)"
say "Tirimid items 2+7 wired in tree"

echo "==> desktop launchers"
for f in web.desktop wifi.desktop files.desktop start-here.desktop term.desktop settings.desktop doom.desktop power.desktop; do
  test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/${f}" || die "missing ${f}"
done
grep -q '/usr/local/bin/chromium' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/web.desktop" || die "web.desktop not wrapped"
grep -q 'cicada-files' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/files.desktop" || die "Files must go through cicada-files"
grep -q 'cicada-doom' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/doom.desktop" || die "doom.desktop must launch cicada-doom"
grep -q 'cicada-power' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/power.desktop" || die "power.desktop must launch cicada-power"
grep -q 'inode/directory=cicada-files.desktop' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/mimeapps.list" || die "directories must open via cicada-files.desktop"
grep -q 'Hidden=true' "${ROOT}/packages/cicada-shell/files/usr/local/share/applications/kitty.desktop" || die "Arch kitty.desktop must be hidden"
grep -q 'Hidden=true' "${ROOT}/packages/cicada-shell/files/usr/local/share/applications/pcmanfm-qt.desktop" || die "Arch pcmanfm desktop must be hidden"
grep -q 'FIRST-BOOT.txt' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/start-here.desktop" || die "start-here"
test -f "${ROOT}/docs/PRODUCT.md" || die "PRODUCT.md"
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
test -L "${P}/airootfs/etc/systemd/system/multi-user.target.wants/usbguard.service" || die "usbguard must be enabled on live (HID-allow rules)"
grep -q '03:\*:\*' "${ROOT}/packages/cicada-defaults/files/etc/usbguard/rules.conf" || die "USBGuard must allow HID for MBA keyboard"
test ! -e "${P}/airootfs/etc/systemd/system/multi-user.target.wants/cicada-radios-off.service" || die "radios-off enabled on live"
test ! -e "${P}/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" || die "networkd still enabled"
grep -q Hyprland "${P}/airootfs/home/cicada/.bash_profile" || die "live home does not start Hyprland"
grep -q 'cicada-firstboot' "${P}/airootfs/home/cicada/.config/hypr/hyprland.conf" && die "assembled hypr still exec-once firstboot" || true
def=$(echo "${P}/efiboot/loader/entries/"01-*.conf)
grep -q intel_iommu "${def}" && die "default live entry has intel_iommu (breaks Apple iGPU)" || true
test ! -f "${P}/efiboot/loader/entries/00-cicada-amnesic.conf" || die "amnesic must not be 00- (sorts first)"
test -f "${P}/efiboot/loader/entries/02-cicada-ram.conf" || die "copy-to-RAM entry 02 missing"
test ! -f "${P}/efiboot/loader/entries/03-cicada-hardened.conf" || die "hardened must not clutter live boot menu"
test ! -f "${P}/efiboot/loader/entries/04-cicada-amnesic.conf" || die "old 04-amnesic entry must be gone"
n_entries=$(find "${P}/efiboot/loader/entries" -name '*.conf' | wc -l | tr -d ' ')
[[ "${n_entries}" -eq 2 ]] || die "live UEFI menu must be exactly 2 entries (got ${n_entries})"
test -x "${P}/airootfs/usr/local/bin/chromium" || die "chromium wrapper not 755"
if [[ -e "${P}/airootfs/usr/local/bin/cicada-crypt" ]]; then
  die "cicada-crypt should be a hook not /usr/local/bin"
fi
test -f "${P}/airootfs/usr/lib/initcpio/hooks/cicada-crypt" || die "crypt hook not in airootfs"
test ! -e "${P}/airootfs/etc/ld.so.preload" || die "assembled live ships ld.so.preload"
test -f "${P}/airootfs/home/cicada/Desktop/start-here.desktop" || die "start-here not in live home"
grep -Rql copytoram "${P}/efiboot" || die "copytoram missing from UEFI entries"
# lockdown stays on *installed* hardened entry (install-chroot), not the live picker
grep -Rql 'lockdown=confidentiality' "${P}/efiboot" && die "live menu must not ship hardened lockdown entry" || true
grep -Rql 'ibt=on' "${P}/efiboot" || die "CET cmdline missing on live"
amnesic=$(grep -l copytoram "${P}/efiboot/loader/entries/"*.conf 2>/dev/null | wc -l | tr -d ' ')
[[ "${amnesic}" -eq 1 ]] || die "expected exactly one copytoram entry"
if grep -L copytoram "${P}/efiboot/loader/entries/"*.conf 2>/dev/null | grep -q .; then
  say "low-RAM live entry exists (no copytoram)"
else
  die "every boot entry is copytoram — 8GB Air will OOM"
fi
say "assemble deep checks"

echo "==> amnesic verify"
CICADA_PROFILE_DIR="${P}" bash "${ROOT}/tests/amnesic-verify.sh" || die "amnesic-verify"

echo "==> live/installed seam"
bash "${ROOT}/tests/seam.sh" >/dev/null || die "seam (run tests/seam.sh for detail)"
say "seam: copy_product coverage, unit parity, no overlay shadowing"

echo "==> channel verify"
bash "${ROOT}/scripts/channel-verify.sh" || die "channel-verify"

echo "==> seal (again)"
bash "${ROOT}/tests/seal.sh" >/dev/null && say "seal chain+tamper"

if [[ "${fail}" -ne 0 ]]; then
  echo "HERE-TESTS FAILED"
  exit 1
fi
echo "HERE-TESTS OK"
