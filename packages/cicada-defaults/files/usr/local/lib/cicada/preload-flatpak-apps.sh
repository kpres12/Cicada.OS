#!/bin/bash
# Build-time only: seed Flatpak apps into the ISO so they need no network on
# first boot. Fired by a pacman hook during pacstrap (see
# etc/pacman.d/hooks/zz-cicada-flatpak-preload.hook) and never runs again —
# mkarchiso strips every airootfs/etc/pacman.d/hooks/* file at the end of the
# build (upstream FS#49347 workaround), so this is not present on the shipped
# system at all, by design, not by accident.
#
# Soft-fail on purpose: this runs partway through a multi-hour pacstrap, and a
# missing preloaded app is a worse outcome to trade for than aborting the whole
# ISO build over it. `cicada-pkg`/Settings -> Install software still installs
# it normally if this step did not land it. Failure is loud, not silent.
set -uo pipefail

APPS=(org.signal.Signal ch.protonmail.protonmail-bridge)

echo "==> cicada: preloading Flatpak apps (${APPS[*]})"

if ! command -v flatpak >/dev/null 2>&1; then
  echo "cicada: preload-flatpak-apps: flatpak not on PATH yet, skipping" >&2
  exit 0
fi

# systemd-resolvconf ships /etc/resolv.conf as a symlink to
# /run/systemd/resolve/stub-resolv.conf, which is only ever populated by a
# *running* systemd-resolved — never true during pacstrap (no init system,
# nothing running but this hook). DNS resolution fails for anything that
# isn't pacman's own downloader (which the outer mkarchiso process handles
# differently). Point resolv.conf at real nameservers just for this
# operation, then restore exactly what was there, so the shipped image still
# gets its DNS from systemd-resolved like every other Cicada install — this
# must never leak a hardcoded resolver onto a real machine.
_orig_is_link=0
_orig_link=""
_orig_backup=""
if [[ -L /etc/resolv.conf ]]; then
  _orig_is_link=1
  _orig_link="$(readlink /etc/resolv.conf)"
elif [[ -f /etc/resolv.conf ]]; then
  _orig_backup="$(mktemp)"
  cp /etc/resolv.conf "${_orig_backup}"
fi
_restore_resolv() {
  rm -f /etc/resolv.conf
  if [[ "${_orig_is_link}" == 1 ]]; then
    ln -sf "${_orig_link}" /etc/resolv.conf
  elif [[ -n "${_orig_backup}" ]]; then
    mv "${_orig_backup}" /etc/resolv.conf
  fi
}
trap _restore_resolv EXIT
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf

# Nothing flatpak starts may hold this script's stdout. pacman reads a hook's
# output until EOF on the pipe, not until the hook exits, so one helper that
# flatpak leaves behind (it daemonises several, and they inherit every open
# descriptor) keeps the pipe open and pacman waits on it forever. That is what
# the weekly reproducible-build job did four times running: the last line below
# printed, the script exited 0, and the build sat silent until the 3 h timeout.
#
# So flatpak writes to a file and the file is replayed afterwards. A survivor
# then holds a log nobody is waiting on.
_log="$(mktemp)"
_run() {
  local rc=0
  "$@" </dev/null >>"${_log}" 2>&1 || rc=$?
  cat "${_log}"
  : > "${_log}"
  return "${rc}"
}

# The survivors are also reaped, because they keep the chroot busy for the
# unmount mkarchiso does next. "Ours" is narrow on purpose: started after this
# point AND rooted in the same directory as this script. /proc here can be the
# build host's own when iso/build.sh runs natively, and nothing outside the
# chroot shares its root inode — so this cannot reach a host process.
_root_id="$(stat -L -c '%d:%i' / 2>/dev/null || true)"
_pids_before=" $(cd /proc 2>/dev/null && echo [0-9]*) "
_reap_strays() {
  local d pid sig
  [[ -n "${_root_id}" ]] || return 0
  for sig in TERM KILL; do
    for d in /proc/[0-9]*; do
      pid="${d#/proc/}"
      [[ "${pid}" == "$$" || "${pid}" == "${BASHPID}" ]] && continue
      [[ "${_pids_before}" == *" ${pid} "* ]] && continue
      [[ "$(stat -L -c '%d:%i' "${d}/root" 2>/dev/null)" == "${_root_id}" ]] || continue
      kill "-${sig}" "${pid}" 2>/dev/null || true
    done
    [[ "${sig}" == TERM ]] && sleep 1
  done
  return 0
}
_finish() {
  _reap_strays
  rm -f "${_log}"
  _restore_resolv
}
trap _finish EXIT

if ! _run flatpak remote-add --if-not-exists --system flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo; then
  echo "cicada: preload-flatpak-apps: could not add flathub remote (no network at build time?) — skipping" >&2
  exit 0
fi

fail=0
for app in "${APPS[@]}"; do
  if _run flatpak install -y --system --noninteractive flathub "${app}"; then
    echo "==> cicada: preloaded ${app}"
  else
    echo "cicada: preload-flatpak-apps: failed to preload ${app} — it will be missing until installed via cicada-pkg" >&2
    fail=1
  fi
done

(( fail == 0 )) && echo "==> cicada: all Flatpak apps preloaded" \
                || echo "cicada: preload-flatpak-apps: finished with failures (see above)" >&2
# Never fail the pacman transaction over this — see the file header.
exit 0
