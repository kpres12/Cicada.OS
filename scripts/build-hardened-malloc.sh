#!/usr/bin/env bash
# Build GrapheneOS hardened_malloc from a pinned tag into an airootfs.
# Not AUR. Upstream: https://github.com/GrapheneOS/hardened_malloc
set -euo pipefail
DEST="${1:?airootfs}"
TAG="${HARDENED_MALLOC_TAG:-14}"
WORK="${HARDENED_MALLOC_WORK:-/tmp/hardened_malloc-src}"

if ! command -v gcc >/dev/null 2>&1; then
  echo "==> hardened_malloc: gcc missing, skip (builder needs gcc make)"
  exit 0
fi

rm -rf "${WORK}"
mkdir -p "${WORK}"
echo "==> hardened_malloc tag ${TAG}"
git clone --depth 1 --branch "${TAG}" https://github.com/GrapheneOS/hardened_malloc.git "${WORK}"
make -C "${WORK}" -j"$(nproc)"
mkdir -p "${DEST}/usr/lib" "${DEST}/etc/cicada"
cp -a "${WORK}/libhardened_malloc.so" "${DEST}/usr/lib/libhardened_malloc.so"
echo "${TAG}" > "${DEST}/etc/cicada/hardened_malloc.version"
echo "==> installed libhardened_malloc.so (${TAG})"
