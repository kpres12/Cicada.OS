#!/usr/bin/env bash
# Remove the setuid/setgid bit from binaries Cicada has no use for.
#
# Every setuid-root binary is a local privilege escalation waiting to be found;
# this class of bug is why pkexec (CVE-2021-4034) and friends keep appearing.
# The ones below exist for multi-user administrative workflows that do not apply
# to a single-owner privacy laptop, so the cheapest defence is to take away the
# privilege rather than hope the parser is correct.
#
# Deliberately KEPT, with reasons, because removing them breaks the machine:
#   sudo, su                 - cicada-netns-helper and cicada-profile-helper
#   passwd                   - cicada-lock reads `passwd -S`; users set passwords
#   unix_chkpwd              - PAM uses it to verify the lock screen. Removing
#                              this makes the machine impossible to unlock.
#   mount, umount            - removable media handling
#   pkexec                   - polkit; the GUI needs it. High-value surface, but
#                              the desktop does not function without it.
#   dbus-daemon-launch-helper- system bus activation
#
# Re-run automatically after every pacman transaction, because upgrading a
# package restores the bits and would silently undo this.
set -uo pipefail

STRIP=(
  /usr/bin/ksu       # Kerberos su. Cicada has no Kerberos; pure attack surface.
  /usr/bin/chfn      # edit GECOS. Long history of setuid bugs, no use here.
  /usr/bin/chsh      # change login shell. Fixed shell on this OS.
  /usr/bin/gpasswd   # group password administration. No such workflow.
  /usr/bin/newgrp    # switch primary group. No such workflow.
  /usr/bin/chage     # password aging policy. Owner uses passwd directly.
  /usr/bin/wall      # setgid tty: broadcast to terminals. Single-owner machine.
  /usr/bin/write     # setgid tty: message another user's terminal.
)

changed=0
for f in "${STRIP[@]}"; do
  [[ -f "${f}" ]] || continue
  # Only act if a set*id bit is actually present, so repeated runs are silent.
  if [[ -u "${f}" || -g "${f}" ]]; then
    chmod u-s,g-s "${f}" 2>/dev/null && changed=$((changed + 1))
  fi
done

if [[ "${changed}" -gt 0 ]]; then
  logger -t cicada "stripped set[ug]id from ${changed} binaries" 2>/dev/null || true
  echo "cicada: stripped set[ug]id from ${changed} binaries"
fi
exit 0
