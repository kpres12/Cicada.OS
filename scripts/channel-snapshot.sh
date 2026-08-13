#!/usr/bin/env bash
# Freeze the package set from a built ISO's pkglist into channel/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="${1:-$(date -u +%Y.%m.%d)}"
SRC="${2:-}"
if [[ -z "${SRC}" ]]; then
  SRC="$(ls -1t "${ROOT}"/out/cicada-*.iso 2>/dev/null | head -1 || true)"
fi
[[ -n "${SRC}" ]] || { echo "usage: channel-snapshot.sh [YYYY.MM.DD] [pkglist-or-iso]"; exit 1; }

OUT="${ROOT}/channel/cicada-stable-${STAMP}.pkglist.txt"
if [[ "${SRC}" == *.txt ]]; then
  cp "${SRC}" "${OUT}"
else
  echo "pass a pkglist from the ISO build (work/profile or airootfs pkglist)." >&2
  echo "example: docker cp <ctr>:/work/mkarchiso/iso/cicada/pkglist.x86_64.txt ${OUT}" >&2
  exit 1
fi
printf '%s\n' "cicada-stable-${STAMP}" > "${ROOT}/channel/CURRENT"
echo "pinned ${OUT}"
