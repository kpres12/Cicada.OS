#!/usr/bin/env bash
# Tirimid "does it act like an OS?" checklist — tree-level proof.
# Hardware boot still required for the real Wi-Fi radio and a rendered Helium
# window; this catches the wiring defects that made items 2 and 7 fail silently.
#
# Run: tests/tirimid.sh   (also from tests/here.sh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

echo "==> Tirimid item 2 — Connect to the internet (Wi-Fi path)"
wifi="${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-wifi"
desk="${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/wifi.desktop"
nmconf="${ROOT}/packages/cicada-defaults/files/etc/NetworkManager/conf.d/cicada.conf"
pkgs="${ROOT}/packages/cicada-install/files/etc/cicada/install-packages.txt"
iso_pkgs="${ROOT}/iso/packages.cicada.x86_64"

test -x "${wifi}" || test -f "${wifi}" || die "cicada-wifi missing"
grep -q 'nmcli device wifi' "${wifi}" || die "cicada-wifi must drive nmcli, not iwd"
grep -q 'cicada-wifi' "${desk}" || die "Desktop WIFI must launch cicada-wifi"
grep -q 'wifi.backend=wpa_supplicant' "${nmconf}" || die "NM must use wpa_supplicant for Broadcom wl"
grep -q 'wifi.scan-rand-mac-address=no' "${nmconf}" || die "scan-rand-mac must be off (empty scan list on wl)"
grep -qx 'networkmanager' "${pkgs}" || die "install must ship NetworkManager"
grep -qx 'wpa_supplicant' "${pkgs}" || die "install must ship wpa_supplicant"
grep -qx 'broadcom-wl' "${pkgs}" || die "install must ship broadcom-wl for MBA BCM4360"
grep -qx 'zenity' "${pkgs}" || die "install must ship zenity (Wi-Fi GUI)"
grep -q '^networkmanager$' "${iso_pkgs}" || die "live ISO packages must include networkmanager"
grep -q '^zenity$' "${iso_pkgs}" || die "live ISO packages must include zenity"
grep -qx 'iwd' "${pkgs}" && die "install must not prefer iwd over NM+wpa" || true
say "Wi-Fi: NM + wpa + broadcom-wl + cicada-wifi + zenity"

echo "==> Tirimid item 7 — Browse the internet (Helium path)"
wrap="${ROOT}/packages/cicada-defaults/files/usr/local/bin/chromium"
web="${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/web.desktop"
scope="${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.cicada.helium.env"
heal="${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/heal-helium.sh"
install_helium="${ROOT}/scripts/install-helium.sh"
firstboot="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot"
sudoers="${ROOT}/packages/cicada-defaults/files/etc/sudoers.d/cicada-profile"

test -f "${wrap}" || die "chromium wrapper missing"
grep -q '/opt/helium/helium-wrapper\|/opt/helium/chrome\|/opt/helium/helium' "${wrap}" || die "wrapper must prefer Helium"
grep -q 'zenity --error' "${wrap}" || die "wrapper must show a dialog when browser is broken"
grep -q '/usr/local/bin/chromium' "${web}" || die "Desktop WEB must launch chromium wrapper"
grep -q 'NETWORK=allow' "${scope}" || die "Helium scope must allow network"
test -f "${heal}" || die "heal-helium.sh missing"
grep -q 'heal-helium' "${firstboot}" || die "firstboot must heal Helium every boot"
grep -q 'heal-helium.sh' "${sudoers}" || die "sudoers must NOPASSWD heal-helium for session trust"
grep -q 'file_permissions\["/opt/helium/' "${install_helium}" || die "install-helium must declare file_permissions for mkarchiso"
grep -q 'heal-helium.sh' "${ROOT}/iso/assemble-profile.sh" || die "assemble must register heal-helium in file_permissions"
grep -q 'chmod 755' "${ROOT}/packages/cicada-install/files/usr/local/bin/cicada-install" \
  || die "cicada-install must chmod Helium after rsync"
say "Helium: wrapper + scope + heal + mkarchiso permissions + install chmod"

echo "==> Tirimid item 6 — Run a game (Doom)"
doom_bin="${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-doom"
doom_desk="${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/doom.desktop"
doom_lock="${ROOT}/channel/doom.lock"
test -f "${doom_bin}" || die "cicada-doom missing"
test -f "${doom_desk}" || die "Desktop Doom icon missing"
grep -q 'chocolate-doom\|cicada-doom' "${doom_desk}" || die "Doom desktop must launch cicada-doom"
grep -q 'engine_sha256=' "${doom_lock}" || die "doom.lock missing engine pin"
grep -q 'wad_sha256=' "${doom_lock}" || die "doom.lock missing Freedoom pin"
grep -q 'install-doom.sh' "${ROOT}/iso/build.sh" || die "ISO build must install Doom"
grep -q 'sdl2' "${pkgs}" || die "install must ship SDL2 for Doom"
grep -q '^sdl2$' "${iso_pkgs}" || die "live ISO must ship SDL2 for Doom"
grep -Eq 'org.cicada.files\|org.cicada.doom' \
  "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" \
  || die "Files and Doom must be host-launch (daily-driver, not sandbox theater)"
grep -q 'cicada-doom.desktop' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/cicada/dock-pinned" \
  || die "Doom must be on the dock"
say "Doom: Chocolate Doom + Freedoom pin, Desktop+dock, SDL2"

echo "==> Tirimid — folder / file system"
files_bin="${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-files"
files_desk="${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/files.desktop"
test -f "${files_bin}" || die "cicada-files missing"
test -f "${files_desk}" || die "Desktop Files icon missing"
grep -q 'pcmanfm-qt' "${files_bin}" || die "Files must launch pcmanfm-qt"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Documents/README.txt" || die "Documents folder missing README"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Downloads/.keep" || die "Downloads missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Pictures/.keep" || die "Pictures missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Music/.keep" || die "Music missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Videos/.keep" || die "Videos missing"
grep -q 'XDG_DOCUMENTS_DIR' "${ROOT}/packages/cicada-shell/files/etc/skel/.config/user-dirs.dirs" \
  || die "user-dirs must declare Documents"
grep -qx 'pcmanfm-qt' "${pkgs}" || die "install must ship pcmanfm-qt"
grep -q 'org.cicada.files' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" \
  || die "Files must not be trapped in a broken sandbox"
say "Files: pcmanfm-qt + Desktop/Documents/Downloads/Pictures/Music/Videos"

echo "==> Tirimid items 1,3,4,5 spine (boot / GUI / editor / compile)"
hypr="${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf"
grep -q 'Hyprland\|hyprland' "${ROOT}/packages/cicada-shell/files/etc/skel/.bash_profile" \
  || die "login must start Hyprland (item 3)"
grep -q 'layout = dwindle' "${hypr}" || die "tiling desktop must exist (item 3)"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/term.desktop" || die "terminal desktop missing (item 4/5)"
grep -q 'cicada-run org.cicada.kitty\|kitty' "${ROOT}/packages/cicada-shell/files/etc/skel/Desktop/term.desktop" \
  || die "terminal launcher broken"
grep -Eq '^(gcc|base-devel)$' "${pkgs}" || say "note: gcc/base-devel not on install list (fizzbuzz needs pacman -S base-devel)"
say "GUI + terminal launchers present"

echo "==> Tirimid item 9 — Destroy the sucker (panic / yank / duress exist)"
test -f "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-panic" || die "panic missing"
test -f "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt" || die "LUKS wipe hook missing"
say "panic + LUKS wipe path present"

if [[ "${fail}" -ne 0 ]]; then
  echo "TIRIMID FAILED — OS checklist wiring broken"
  exit 1
fi
echo "TIRIMID OK"
