#!/usr/bin/env bash
# Make Cicada's Flatpak permission floors actually hold.
#
# The floors are written with `flatpak override --system`, and the comment next
# to them used to claim that a system-level override could not be granted back
# by the user. That is false, and it was measured rather than argued: with a real
# app installed, `flatpak info --show-permissions` reports
#
#   after `flatpak override --system --nofilesystem=home`   filesystems=
#   after `flatpak override --user   --filesystem=home`     filesystems=home;
#
# User overrides are merged last and win. So every floor — home denied, no X11,
# no standing camera or microphone — could be removed by one command run as the
# user, which means also by anything executing as the user. That reduces the
# floors from a boundary to a suggestion, on the one path that now installs all
# graphical software.
#
# Flatpak has no "locked" system override. What it does have is a per-user
# installation directory it must be able to write to before it can record a user
# override at all. Root-owning that directory blocks user overrides while leaving
# system-installed apps fully usable — verified: the user still lists them, still
# launches them, and still gets the floors.
#
# The directory must contain root-owned content. An empty root-owned directory
# sits inside a user-writable parent, so the user can simply remove it and make
# their own; with root-owned content inside, rm fails and it survives. Both cases
# were tested.
#
# This is the project's own rule applied to Flatpak: a protection users switch
# off protects nobody.
set -uo pipefail

[[ ${EUID} -eq 0 ]] || { echo "lock-flatpak-overrides: root only" >&2; exit 1; }

locked=0
skipped=0

lock_home() {
  local home="$1" d="${1}/.local/share/flatpak"

  # A pre-existing per-user installation means real apps live here. Taking it
  # over would break them, and silently breaking a user's applications to
  # tighten a permission is a bad trade — say so and leave it alone.
  if [[ -d "${d}/repo" || -d "${d}/app" ]]; then
    echo "lock-flatpak-overrides: ${d} holds a per-user Flatpak installation; leaving it." >&2
    echo "  Floors there can still be overridden by the user. Move those apps to the" >&2
    echo "  system installation (cicada-pkg) and re-run this to close it." >&2
    skipped=$((skipped + 1))
    return 0
  fi

  install -d -o root -g root -m 0755 "${d}" 2>/dev/null || return 0
  install -d -o root -g root -m 0755 "${d}/overrides" 2>/dev/null || true

  # Non-empty and root-owned, so the directory cannot be removed and replaced by
  # a user-writable one. This file is the thing that makes the lock stick.
  local marker="${d}/.cicada-managed"
  if [[ ! -f "${marker}" ]]; then
    printf '%s\n' \
      "Owned by root on purpose." \
      "" \
      "Cicada applies Flatpak permission floors with 'flatpak override --system'." \
      "User overrides are merged after system ones and win, so a writable" \
      "per-user Flatpak directory would let any process running as you remove" \
      "those floors with a single command." \
      "" \
      "System-installed apps are unaffected: they list, launch and keep working." \
      "Install applications with cicada-pkg, which installs --system." \
      > "${marker}" 2>/dev/null || true
    chown root:root "${marker}" 2>/dev/null || true
    chmod 0644 "${marker}" 2>/dev/null || true
  fi
  locked=$((locked + 1))
}

if [[ $# -gt 0 ]]; then
  for h in "$@"; do [[ -d "${h}" ]] && lock_home "${h}"; done
else
  for h in /home/*; do [[ -d "${h}" ]] && lock_home "${h}"; done
  [[ -d /root ]] && lock_home /root
fi

if [[ "${locked}" -gt 0 ]]; then
  logger -t cicada "flatpak override dir locked for ${locked} home(s)" 2>/dev/null || true
fi
exit 0
