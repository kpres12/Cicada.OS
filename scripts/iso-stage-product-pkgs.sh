#!/usr/bin/env bash
# Build Cicada product packages into a tiny local repo for mkarchiso pacstrap.
# When this succeeds, assemble-profile skips rsync of those trees so pacman owns
# the files on the live image (and etched systems get the same packages).
#
# Usage: iso-stage-product-pkgs.sh <repo-out-dir>
# Requires: makepkg, repo-add (Arch builder / Docker). No-op exit 0 otherwise.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?repo out dir}"

command -v makepkg >/dev/null 2>&1 || {
  echo "iso-stage-product-pkgs: makepkg missing — rsync fallback" >&2
  exit 0
}
command -v repo-add >/dev/null 2>&1 || {
  echo "iso-stage-product-pkgs: repo-add missing — rsync fallback" >&2
  exit 0
}

rm -rf "${OUT}"
mkdir -p "${OUT}"

# File-tree + malloc on the ISO. Helium stays install-helium.sh for fail-fast
# preflight (and lands as unmanaged /opt until channel cicada-helium upgrades).
export CICADA_BUILD_HELIUM="${CICADA_BUILD_HELIUM:-0}"
export CICADA_BUILD_MALLOC="${CICADA_BUILD_MALLOC:-1}"
bash "${ROOT}/scripts/channel-build-meta.sh" "${OUT}"

# Stamp so assemble-profile knows pacman ownership is active.
if compgen -G "${OUT}/cicada-shell-*.pkg.tar.*" >/dev/null; then
  printf '1\n' > "${OUT}/.cicada-product-pacman"
  echo "iso-stage-product-pkgs: ready at ${OUT}"
else
  echo "iso-stage-product-pkgs: no cicada-shell package — rsync fallback" >&2
  rm -f "${OUT}/.cicada-product-pacman"
fi
