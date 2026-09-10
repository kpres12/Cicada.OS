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

if ! flatpak remote-add --if-not-exists --system flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo; then
  echo "cicada: preload-flatpak-apps: could not add flathub remote (no network at build time?) — skipping" >&2
  exit 0
fi

fail=0
for app in "${APPS[@]}"; do
  if flatpak install -y --system --noninteractive flathub "${app}"; then
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
