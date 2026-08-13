#!/usr/bin/env bash
# Hide Arch .desktop entries so only Cicada launchers appear in generic XDG menus.
# cicada-wofi already uses /usr/share/cicada/launchers only; this seals other paths.
set -euo pipefail
[[ ${EUID} -eq 0 ]] || { echo "hide-arch-desktops: root only" >&2; exit 1; }

ARCH_APPS=/usr/share/applications
CICADA_APPS=/usr/share/cicada/launchers/applications
OVERRIDE=/usr/local/share/applications
MARKER=/var/lib/cicada/hide-arch-desktops-done

mkdir -p "${OVERRIDE}" /var/lib/cicada

# Basenames Cicada ships in its catalog — do not hide those names if Arch also has them
# (e.g. chromium.desktop): the Cicada launcher wins via XDG_DATA_DIRS order, but we still
# write an override that points discovery away from raw Arch Exec lines when names collide.
allow=()
if [[ -d "${CICADA_APPS}" ]]; then
  while IFS= read -r -d '' f; do
    allow+=("$(basename "${f}")")
  done < <(find "${CICADA_APPS}" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
fi

is_allowed() {
  local b="$1" a
  for a in "${allow[@]+"${allow[@]}"}"; do
    [[ "${a}" == "${b}" ]] && return 0
  done
  return 1
}

[[ -d "${ARCH_APPS}" ]] || { touch "${MARKER}"; exit 0; }

count=0
for src in "${ARCH_APPS}"/*.desktop; do
  [[ -e "${src}" ]] || continue
  base="$(basename "${src}")"
  if is_allowed "${base}"; then
    continue
  fi
  dest="${OVERRIDE}/${base}"
  # Preserve a prior Cicada-authored override (e.g. Hidden kitty) if already present
  # with Exec=cicada-run — still force Hidden.
  {
    echo '[Desktop Entry]'
    echo 'Hidden=true'
    echo 'NoDisplay=true'
    echo "Name=Hidden by Cicada (${base})"
    echo 'Type=Application'
  } > "${dest}"
  count=$((count + 1))
done

# Always hide the raw Arch terminals / file managers even if allowlist glitched.
for base in kitty.desktop pcmanfm-qt.desktop thunar.desktop org.kde.dolphin.desktop \
            alacritty.desktop foot.desktop org.gnome.Nautilus.desktop; do
  dest="${OVERRIDE}/${base}"
  if [[ ! -f "${dest}" ]] || ! grep -q 'Hidden=true' "${dest}" 2>/dev/null; then
    {
      echo '[Desktop Entry]'
      echo 'Hidden=true'
      echo 'NoDisplay=true'
      echo "Name=Hidden by Cicada (${base})"
      echo 'Type=Application'
    } > "${dest}"
  fi
done

echo "hide-arch-desktops: hid ${count} Arch launchers under ${OVERRIDE}"
touch "${MARKER}"
