#!/usr/bin/env bash
# Record (or verify) Hyprland desk-stack NEVRs into channel/hyprland.lock.
# Run on Arch / Docker builder after a known-good ISO or desk boot.
#
#   channel-pin-hyprland.sh          # write lock from installed packages
#   channel-pin-hyprland.sh --check  # exit 1 if installed ≠ lock
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${ROOT}/channel/hyprland.lock"
MODE="${1:-write}"

PKGS=(
  hyprland
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  hyprpaper
  hyprlock
  hypridle
  hyprpolkitagent
  waybar
  nwg-dock-hyprland
  wofi
)

nevr() {
  local name="$1"
  if command -v pacman >/dev/null 2>&1; then
    pacman -Q "${name}" 2>/dev/null | awk '{print $2}' && return 0
  fi
  # Offline: pull from the channel pkglist named in CURRENT / lock.
  local pin list
  pin="$(cat "${ROOT}/channel/CURRENT" 2>/dev/null || true)"
  list="${ROOT}/channel/${pin}.pkglist.txt"
  [[ -f "${list}" ]] || list="$(ls -1 "${ROOT}/channel"/cicada-stable-*.pkglist.txt 2>/dev/null | sort | tail -1 || true)"
  [[ -f "${list}" ]] || return 1
  awk -v n="${name}" '$1 == n { print $2; exit }' "${list}"
}

if [[ "${MODE}" == "--check" || "${MODE}" == "check" ]]; then
  [[ -f "${LOCK}" ]] || { echo "channel-pin-hyprland: missing ${LOCK}" >&2; exit 1; }
  drift=0
  for p in "${PKGS[@]}"; do
    want="$(awk -F= -v n="${p}" '$1 == n { print $2; exit }' "${LOCK}")"
    got="$(nevr "${p}" || true)"
    if [[ -z "${want}" ]]; then
      echo "channel-pin-hyprland: ${p} not in lock" >&2
      drift=1
      continue
    fi
    if [[ -z "${got}" ]]; then
      echo "channel-pin-hyprland: ${p} not installed / not in pkglist" >&2
      drift=1
      continue
    fi
    if [[ "${want}" != "${got}" ]]; then
      echo "channel-pin-hyprland: DRIFT ${p} lock=${want} have=${got}" >&2
      drift=1
    else
      echo "channel-pin-hyprland: ok ${p}=${got}"
    fi
  done
  exit "${drift}"
fi

pin="$(cat "${ROOT}/channel/CURRENT" 2>/dev/null || echo unknown)"
{
  echo "# Hyprland desk stack pin — Arch NEVRs Cicada last tested as a unit."
  echo "# Updated by scripts/channel-pin-hyprland.sh on an Arch/Docker builder."
  echo "# When Arch breaks the desk, rebuild these from upstream tags into cicada-stable"
  echo "# (see docs/USERLAND.md) rather than chasing raw rolling mid-session."
  echo "#"
  echo "# format: name=version-release"
  echo "channel=${pin}"
  for p in "${PKGS[@]}"; do
    v="$(nevr "${p}" || true)"
    if [[ -z "${v}" ]]; then
      echo "channel-pin-hyprland: cannot resolve ${p}" >&2
      exit 1
    fi
    echo "${p}=${v}"
  done
} > "${LOCK}"
echo "channel-pin-hyprland: wrote ${LOCK}"
