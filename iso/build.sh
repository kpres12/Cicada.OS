#!/usr/bin/env bash
# Build the Cicada.OS x86_64 ISO with mkarchiso.
# Intended to run inside the linux/amd64 Arch builder container (or native Arch).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${CICADA_OUT:-${ROOT}/out}"
WORK="${CICADA_WORK:-${ROOT}/work}"
PROFILE="${CICADA_PROFILE_DIR:-${WORK}/profile}"

if ! command -v mkarchiso >/dev/null 2>&1; then
  echo "error: mkarchiso not found. Install archiso on an Arch host." >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "error: ISO target is x86_64 (Intel MBA). This host is $(uname -m)." >&2
  echo "  On Apple Silicon, use: ./scripts/build-iso-docker.sh" >&2
  exit 1
fi

mkdir -p "${OUT}" "${WORK}"
export CICADA_PROFILE_DIR="${PROFILE}"
"${ROOT}/iso/assemble-profile.sh"

if [[ -x "${ROOT}/scripts/build-hardened-malloc.sh" ]]; then
  "${ROOT}/scripts/build-hardened-malloc.sh" "${PROFILE}/airootfs" || \
    echo "==> hardened_malloc build skipped (ISO still boots; preload is a no-op)"
fi

# Official Helium tarball (hash-pinned). Fail the ISO if this cannot land —
# Chromium is no longer the product browser.
"${ROOT}/scripts/install-helium.sh" "${PROFILE}/airootfs"

# Official Chocolate Doom + Freedoom (hash-pinned). Tirimid item 6 — required.
"${ROOT}/scripts/install-doom.sh" "${PROFILE}/airootfs"

# Prove Helium + wallpaper landed before the long pacstrap (fail fast).
helium_bin=""
for cand in \
  "${PROFILE}/airootfs/opt/helium/helium" \
  "${PROFILE}/airootfs/opt/helium/chrome" \
  "${PROFILE}/airootfs/opt/helium/helium-wrapper"
do
  if [[ -x "${cand}" ]]; then
    helium_bin="${cand}"
    break
  fi
done
[[ -n "${helium_bin}" ]] || {
  echo "error: Helium not executable in airootfs after install-helium.sh" >&2
  ls -la "${PROFILE}/airootfs/opt/helium" 2>&1 | head -20 >&2 || true
  exit 1
}
wall="${PROFILE}/airootfs/usr/share/cicada/wallpapers/cicada-3301.png"
[[ -f "${wall}" ]] || {
  echo "error: wallpaper missing at ${wall}" >&2
  exit 1
}
grep -q 'cicada-wallpaper' "${PROFILE}/airootfs/etc/skel/.config/hypr/hyprland.conf" \
  || grep -q 'cicada-wallpaper' "${PROFILE}/airootfs/home/cicada/.config/hypr/hyprland.conf" \
  || echo "==> warning: cicada-wallpaper not in hyprland.conf (desk may stay void)"
echo "==> preflight OK: Helium=$(basename "${helium_bin}") wallpaper=$(basename "${wall}")"

echo "==> mkarchiso  work=${WORK}/mkarchiso  out=${OUT}"
rm -rf "${WORK}/mkarchiso"
mkdir -p "${WORK}/mkarchiso"

run_mkarchiso() {
  local MKARCHISO=(mkarchiso -v -w "${WORK}/mkarchiso" -o "${OUT}" "${PROFILE}")
  if [[ "${EUID}" -ne 0 ]]; then
    MKARCHISO=(sudo "${MKARCHISO[@]}")
  fi
  "${MKARCHISO[@]}"
}

# Under qemu-amd64, a killed prior pacstrap can leave the work volume poisoned
# even after rm -rf; one clean retry covers the perl/desc abort class.
if ! run_mkarchiso; then
  echo "==> mkarchiso failed — scrubbing work and retrying once"
  rm -rf "${WORK}/mkarchiso"
  mkdir -p "${WORK}/mkarchiso"
  # Drop any stale locks from a crashed privileged mount
  sleep 2
  run_mkarchiso
fi

# Persist pacman pkg cache → local cicada-stable repo (next assemble embeds it).
PKG_CACHE=""
for cand in \
  "${WORK}/mkarchiso/x86_64/airootfs/var/cache/pacman/pkg" \
  "${WORK}/mkarchiso/airootfs/var/cache/pacman/pkg" \
  "${WORK}/mkarchiso/pacman/pkg" \
  /var/cache/pacman/pkg
do
  # mkarchiso pacstraps with -c, so the packages land in the *builder's* cache
  # (a persistent docker volume), not in the airootfs. The airootfs paths are
  # kept first for older archiso behaviour; /var/cache/pacman/pkg is the one
  # that actually has anything today.
  if [[ -d "${cand}" ]] && compgen -G "${cand}/*.pkg.tar.*" >/dev/null 2>&1; then
    PKG_CACHE="${cand}"
    break
  fi
done
if [[ -n "${PKG_CACHE}" ]]; then
  echo "==> channel repo from ${PKG_CACHE}"
  mkdir -p "${OUT}/channel-repo"
  if [[ -x "${ROOT}/scripts/channel-build-repo.sh" ]] || [[ -f "${ROOT}/scripts/channel-build-repo.sh" ]]; then
    bash "${ROOT}/scripts/channel-build-repo.sh" "${PKG_CACHE}" "${OUT}/channel-repo" || \
      echo "==> channel-build-repo skipped (non-fatal)"
    # No tree copy into channel/repo: /src is mounted read-only in the builder,
    # so it never worked, and the repo is ~2 GiB — it belongs in out/ (published
    # to the channel-latest release), not in the git tree or on the ISO.
  fi
else
  echo "==> no pacman pkg cache found under ${WORK}/mkarchiso (channel repo deferred)"
fi

echo "==> ISO(s):"
ls -lh "${OUT}"/*.iso

# Always point flash scripts / humans at the newest image (same-day rebuilds
# overwrite cicada-YYYY.MM.DD-x86_64.iso; the symlink tracks whichever won).
newest="$(ls -1t "${OUT}"/cicada-*.iso 2>/dev/null | grep -v 'cicada-latest' | head -1 || true)"
if [[ -n "${newest}" ]]; then
  ln -sfn "$(basename "${newest}")" "${OUT}/cicada-latest-x86_64.iso"
  echo "==> latest -> ${OUT}/cicada-latest-x86_64.iso -> $(basename "${newest}")"
  ls -lh "${newest}" "${OUT}/cicada-latest-x86_64.iso"
fi
