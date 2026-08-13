#!/usr/bin/env bash
# Install Cicada file layer onto a running Arch system (dev/test, not a full distro install).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "re-run with sudo" >&2
  exit 1
fi

echo "==> Installing cicada-defaults"
cp -a "${ROOT}/packages/cicada-defaults/files/." /

echo "==> Installing cicada-shell (system skel + bins)"
cp -a "${ROOT}/packages/cicada-shell/files/." /

echo "==> Installing cicada-profiles"
cp -a "${ROOT}/packages/cicada-profiles/files/." /

chmod 755 /usr/local/bin/cicada-* 2>/dev/null || true
systemctl daemon-reload
systemctl enable cicada-radios-off.service || true

TARGET_USER="${SUDO_USER:-}"
if [[ -n "${TARGET_USER}" && "${TARGET_USER}" != root ]]; then
  HOME_DIR="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  echo "==> Seeding Hyprland config for ${TARGET_USER}"
  install -d -o "${TARGET_USER}" -g "${TARGET_USER}" "${HOME_DIR}/.config"
  cp -a /etc/skel/.config/. "${HOME_DIR}/.config/"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.config/hypr" \
    "${HOME_DIR}/.config/waybar" "${HOME_DIR}/.config/kitty" 2>/dev/null || true
fi

echo "Cicada layer installed. Log out/in or restart Hyprland."