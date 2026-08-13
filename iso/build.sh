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

echo "==> mkarchiso  work=${WORK}/mkarchiso  out=${OUT}"
rm -rf "${WORK}/mkarchiso"
mkdir -p "${WORK}/mkarchiso"

MKARCHISO=(mkarchiso -v -w "${WORK}/mkarchiso" -o "${OUT}" "${PROFILE}")
if [[ "${EUID}" -ne 0 ]]; then
  MKARCHISO=(sudo "${MKARCHISO[@]}")
fi
"${MKARCHISO[@]}"

# Persist pacman pkg cache → local cicada-stable repo (next assemble embeds it).
PKG_CACHE=""
for cand in \
  "${WORK}/mkarchiso/x86_64/airootfs/var/cache/pacman/pkg" \
  "${WORK}/mkarchiso/airootfs/var/cache/pacman/pkg" \
  "${WORK}/mkarchiso/pacman/pkg"
do
  if [[ -d "${cand}" ]] && compgen -G "${cand}/*.pkg.tar.*" >/dev/null 2>&1; then
    PKG_CACHE="${cand}"
    break
  fi
done
if [[ -n "${PKG_CACHE}" ]]; then
  echo "==> channel repo from ${PKG_CACHE}"
  mkdir -p "${OUT}/channel-repo" "${ROOT}/channel/repo"
  if [[ -x "${ROOT}/scripts/channel-build-repo.sh" ]] || [[ -f "${ROOT}/scripts/channel-build-repo.sh" ]]; then
    bash "${ROOT}/scripts/channel-build-repo.sh" "${PKG_CACHE}" "${OUT}/channel-repo" || \
      echo "==> channel-build-repo skipped (non-fatal)"
    # Keep a tree copy for the next assemble-profile embed
    rsync -a "${OUT}/channel-repo/" "${ROOT}/channel/repo/" 2>/dev/null || true
  fi
else
  echo "==> no pacman pkg cache found under ${WORK}/mkarchiso (channel repo deferred)"
fi

echo "==> ISO(s):"
ls -lh "${OUT}"/*.iso
