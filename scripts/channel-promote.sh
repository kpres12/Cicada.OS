#!/usr/bin/env bash
# Promote a snapshot to CURRENT. Does not publish blobs yet (warehouse comes later).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:?usage: channel-promote.sh cicada-stable-YYYY.MM.DD}"
[[ -f "${ROOT}/channel/${NAME}.pkglist.txt" ]] || { echo "missing lockfile"; exit 1; }
printf '%s\n' "${NAME}" > "${ROOT}/channel/CURRENT"
echo "CURRENT -> ${NAME}"
echo "next: repo-add the matching .pkg.tar.zst files into channel/repo/"
