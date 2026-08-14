#!/usr/bin/env bash
# Build product meta packages into the cicada-stable repo (Arch builder only).
# Called from channel-build-repo.sh when makepkg is available.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/out/channel-repo}"

command -v makepkg >/dev/null 2>&1 || {
  echo "channel-build-meta: makepkg missing — skip" >&2
  exit 0
}

mkdir -p "${OUT}"
built=0
for name in cicada-desktop; do
  src="${ROOT}/packages/${name}"
  [[ -f "${src}/PKGBUILD" ]] || continue
  work="$(mktemp -d)"
  cp -a "${src}/." "${work}/"
  (
    cd "${work}"
    # Meta packages are arch=any; no deps needed at build time for empty package().
    makepkg -f --nodeps --nocheck 2>/dev/null || makepkg -f --nodeps
  )
  shopt -s nullglob
  for pkg in "${work}"/*.pkg.tar.zst "${work}"/*.pkg.tar.xz; do
    cp -a "${pkg}" "${OUT}/"
    echo "channel-build-meta: $(basename "${pkg}")"
    built=$((built + 1))
  done
  rm -rf "${work}"
done

if [[ "${built}" -eq 0 ]]; then
  echo "channel-build-meta: nothing built"
  exit 0
fi

if command -v repo-add >/dev/null 2>&1; then
  (
    cd "${OUT}"
    rm -f cicada-stable.db* cicada-stable.files* 2>/dev/null || true
    repo-add cicada-stable.db.tar.zst ./*.pkg.tar.zst ./*.pkg.tar.xz 2>/dev/null \
      || repo-add cicada-stable.db.tar.zst ./*.pkg.tar.zst
  )
fi
echo "channel-build-meta: ${built} package(s) → ${OUT}"
