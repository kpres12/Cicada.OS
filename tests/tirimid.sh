#!/usr/bin/env bash
# Revised Tirimid 10-point OS checklist — tree-level proof that Cicada is an OS,
# not a bag of security knobs. Hardware still required for real pixels/radio.
#
#  1 Get a graphical system running
#  2 Change the resolution
#  3 Program fizzbuzz, compile, and run it
#  4 Install a new program
#  5 Run a game
#  6 Browse the internet
#  7 Explore what makes it special
#  8 Power off and reboot
#  9 Check the style
# 10 Destroy the sucker
#
# Run: tests/tirimid.sh   (also from tests/here.sh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

pkgs="${ROOT}/packages/cicada-install/files/etc/cicada/install-packages.txt"
iso_pkgs="${ROOT}/iso/packages.cicada.x86_64"
hypr="${ROOT}/packages/cicada-shell/files/etc/skel/.config/hypr/hyprland.conf"
settings="${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-settings"
skel_desk="${ROOT}/packages/cicada-shell/files/etc/skel/Desktop"

echo "==> 1 — Graphical system"
grep -q 'Hyprland\|hyprland' "${ROOT}/packages/cicada-shell/files/etc/skel/.bash_profile" \
  || die "login must start Hyprland"
grep -q 'exec-once = waybar\|waybar' "${hypr}" || die "Waybar must start"
grep -q 'exec-once = cicada-dock\|cicada-dock' "${hypr}" || die "dock must start"
grep -q 'exec-once = pcmanfm-qt --desktop' "${hypr}" || die "desktop icons (pcmanfm) must start"
grep -q 'layout = dwindle' "${hypr}" || die "tiling desktop must exist"
test -f "${skel_desk}/term.desktop" || die "terminal desktop icon missing"
say "Hyprland + dock + desktop icons + terminal"

echo "==> 2 — Change the resolution"
grep -q 'Resolution' "${settings}" || die "Settings Displays must offer Resolution"
grep -q 'hyprctl keyword monitor' "${settings}" || die "resolution must apply via hyprctl"
say "Settings → Displays → Resolution… (GUI)"

echo "==> 3 — Fizzbuzz compile + run"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Documents/fizzbuzz.c" \
  || die "Documents/fizzbuzz.c starter missing"
grep -qx 'nano' "${pkgs}" || die "install must ship nano (editor)"
grep -qx 'base-devel' "${pkgs}" || die "install must ship base-devel (gcc/make)"
grep -q '^nano$' "${iso_pkgs}" || die "live ISO must ship nano"
grep -q '^base-devel$' "${iso_pkgs}" || die "live ISO must ship base-devel"
grep -qx 'python' "${pkgs}" || die "install must ship python"
grep -qx 'python-pip' "${pkgs}" || die "install must ship python-pip"
grep -q 'flatpak-install\|Spotify' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-pkg" \
  || die "cicada-pkg must offer Flatpak apps"
grep -q 'com.spotify.Client' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-pkg-helper" \
  || die "pkg-helper must allowlist Spotify Flatpak"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Documents/hello.py" || die "hello.py starter missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Documents/PROGRAMS.txt" || die "PROGRAMS.txt missing"
say "nano + base-devel + python + pip + Flatpak app path"

echo "==> 4 — Install a new program"
test -f "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-pkg" || die "cicada-pkg GUI missing"
test -f "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-pkg-helper" \
  || die "cicada-pkg-helper missing"
grep -q 'pacman -Sy' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-pkg-helper" \
  || die "helper must call pacman"
grep -q 'cicada-pkg-helper' "${ROOT}/packages/cicada-defaults/files/etc/sudoers.d/cicada-profile" \
  || die "sudoers must NOPASSWD cicada-pkg-helper"
grep -q 'Install software' "${settings}" || die "Settings must offer Install software"
say "Settings → Install software… (pacman + Flatpak apps)"

echo "==> 5 — Run a game (Doom)"
test -f "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-doom" || die "cicada-doom missing"
test -f "${skel_desk}/doom.desktop" || die "Desktop Doom icon missing"
grep -q 'engine_sha256=' "${ROOT}/channel/doom.lock" || die "doom.lock missing"
grep -q 'install-doom.sh' "${ROOT}/iso/build.sh" || die "ISO must build Doom"
grep -q 'sdl2' "${pkgs}" || die "SDL2 required for Doom"
say "Doom Desktop + dock path + channel pin"

echo "==> 6 — Browse the internet"
wrap="${ROOT}/packages/cicada-defaults/files/usr/local/bin/chromium"
test -f "${wrap}" || die "chromium/Helium wrapper missing"
grep -q 'zenity --error' "${wrap}" || die "browser must show GUI on failure"
test -f "${skel_desk}/web.desktop" || die "Desktop Web icon missing"
grep -q 'NETWORK=allow' \
  "${ROOT}/packages/cicada-shell/files/etc/skel/.local/share/cicada/scopes/org.cicada.helium.env" \
  || die "Helium must allow network"
grep -q 'heal-helium' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-firstboot" \
  || die "Helium exec-bit heal missing"
grep -q 'cicada-wifi' "${skel_desk}/wifi.desktop" || die "Wi-Fi desktop missing (browse needs net)"
say "Web + Helium heal + Wi-Fi GUI"

echo "==> 7 — Explore what makes it special"
test -f "${skel_desk}/settings.desktop" || die "Settings desktop missing"
grep -q 'App permissions\|Scopes\|Camera & microphone\|Profiles' "${settings}" \
  || die "Settings must surface Cicada-specific controls"
grep -q 'CICADA_LUKS_MAX_FAIL\|luksErase' \
  "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt" \
  || die "special: LUKS attempt-cap wipe missing"
say "Settings specials + LUKS/duress story present"

echo "==> 8 — Power off and reboot"
test -f "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-power" || die "cicada-power missing"
test -f "${skel_desk}/power.desktop" || die "Desktop Power icon missing"
grep -q 'systemctl reboot\|reboot' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-power" \
  || die "power must reboot"
grep -q 'systemctl poweroff\|poweroff' "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-power" \
  || die "power must shut down"
grep -q 'cicada-power\|Power' "${settings}" || die "Settings must offer Power"
say "Power Desktop + Settings (GUI reboot/shutdown)"

echo "==> 9 — Check the style"
grep -q 'Appearance\|Wallpaper\|Dark\|Light' "${settings}" || die "Appearance GUI missing"
grep -q 'apply_wallpaper\|Wallpaper' "${settings}" || die "wallpaper picker missing"
test -d "${ROOT}/packages/cicada-shell/files/usr/share/cicada/wallpapers" \
  || test -d "${ROOT}/packages/cicada-defaults/files/usr/share/cicada/wallpapers" \
  || die "stock wallpapers missing"
say "Appearance: wallpaper + dark/light"

echo "==> 10 — Destroy the sucker"
test -f "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-panic" || die "panic missing"
test -f "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt" \
  || die "LUKS wipe hook missing"
say "panic + LUKS wipe path"

echo "==> Files / folders (needed for 3 and daily use)"
test -f "${ROOT}/packages/cicada-shell/files/usr/local/bin/cicada-files" || die "cicada-files missing"
test -f "${skel_desk}/files.desktop" || die "Files desktop missing"
test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Documents/.keep" \
  || test -f "${ROOT}/packages/cicada-shell/files/etc/skel/Documents/README.txt" \
  || die "Documents missing"
say "Files app + home folders"

if [[ "${fail}" -ne 0 ]]; then
  echo "TIRIMID FAILED — revised 10-point OS checklist broken in tree"
  exit 1
fi
echo "TIRIMID OK (10-point wiring)"
