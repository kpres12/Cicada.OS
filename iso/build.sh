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

echo "==> mkarchiso  work=${WORK}/mkarchiso  out=${OUT}"
rm -rf "${WORK}/mkarchiso"
mkdir -p "${WORK}/mkarchiso"

MKARCHISO=(mkarchiso -v -w "${WORK}/mkarchiso" -o "${OUT}" "${PROFILE}")
if [[ "${EUID}" -ne 0 ]]; then
  MKARCHISO=(sudo "${MKARCHISO[@]}")
fi
"${MKARCHISO[@]}"

echo "==> ISO(s):"
ls -lh "${OUT}"/*.iso
