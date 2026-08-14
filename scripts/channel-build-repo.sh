#!/usr/bin/env bash
# Build a local cicada-stable pacman repo from a pacman pkg cache directory.
# Usage: channel-build-repo.sh <pkg-cache-dir> <repo-out-dir>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${1:-}"
OUT="${2:-${ROOT}/out/channel-repo}"

if [[ -z "${CACHE}" || ! -d "${CACHE}" ]]; then
  echo "usage: channel-build-repo.sh <pkg-cache-dir> [repo-out-dir]" >&2
  exit 1
fi

mkdir -p "${OUT}"
shopt -s nullglob
pkgs=("${CACHE}"/*.pkg.tar.zst "${CACHE}"/*.pkg.tar.xz)
if [[ ${#pkgs[@]} -eq 0 ]]; then
  echo "channel-build-repo: no packages in ${CACHE}" >&2
  exit 2
fi

# Copy (hardlink when possible) into the repo dir.
#
# The .sig beside each package is not optional. Once the Cicada pubkey is on a
# machine, cicada-channel-enable resolves SigLevel to Required, which is
# PackageRequired as well as DatabaseRequired — our key signs the database, but
# each package still has to carry its own Arch developer signature. Shipping the
# packages without their sigs produces a repo that fails every install with
# "invalid or corrupted package", which reads as a broken mirror.
missing_sig=0
for p in "${pkgs[@]}"; do
  base="$(basename "${p}")"
  if [[ ! -e "${OUT}/${base}" ]]; then
    cp -an "${p}" "${OUT}/${base}" 2>/dev/null || cp -a "${p}" "${OUT}/${base}"
  fi
  if [[ -f "${p}.sig" ]]; then
    [[ -e "${OUT}/${base}.sig" ]] || cp -a "${p}.sig" "${OUT}/${base}.sig"
  else
    missing_sig=$((missing_sig + 1))
  fi
done

if (( missing_sig > 0 )); then
  echo "channel-build-repo: WARNING ${missing_sig}/${#pkgs[@]} package(s) have no .sig" >&2
  echo "channel-build-repo: those will be rejected on any machine with the Cicada key" >&2
fi

if ! command -v repo-add >/dev/null 2>&1; then
  echo "channel-build-repo: repo-add missing (need pacman on Arch builder)" >&2
  exit 3
fi

rm -f "${OUT}/cicada-stable.db"* "${OUT}/cicada-stable.files"* 2>/dev/null || true
(
  cd "${OUT}"
  repo-add cicada-stable.db.tar.zst ./*.pkg.tar.zst ./*.pkg.tar.xz 2>/dev/null \
    || repo-add cicada-stable.db.tar.zst ./*.pkg.tar.zst
)

echo "channel-build-repo: wrote ${OUT}/cicada-stable.db*"

# Product meta-packages (cicada-desktop, …) when builder has makepkg.
if [[ -x "${ROOT}/scripts/channel-build-meta.sh" ]] || [[ -f "${ROOT}/scripts/channel-build-meta.sh" ]]; then
  bash "${ROOT}/scripts/channel-build-meta.sh" "${OUT}" || \
    echo "channel-build-repo: meta packages skipped (non-fatal)"
fi

# Optional sign
if [[ -x "${ROOT}/scripts/channel-sign.sh" ]]; then
  "${ROOT}/scripts/channel-sign.sh" "${OUT}" || true
fi
