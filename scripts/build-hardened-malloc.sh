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

# GCC 16 / libstdc++ dropped std::__throw_bad_alloc. Tag 14 still uses it.
python3 - "${WORK}/new.cc" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
text = text.replace("std::__throw_bad_alloc();", "throw std::bad_alloc();")
p.write_text(text)
PY

# ISO is built in QEMU amd64; -march=native would follow the emulator, not the Air.
# x86-64-v3 = AVX2/BMI (Broadwell MBA 2015–2017 and typical daily-driver PCs).
python3 - "${WORK}/Makefile" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
if "-march=native" not in text:
    raise SystemExit("Makefile missing -march=native")
p.write_text(text.replace("-march=native", "-march=x86-64-v3"))
PY
make -C "${WORK}" -j"$(nproc)"

so="$(find "${WORK}" -name 'libhardened_malloc.so' -print | head -n 1)"
if [[ -z "${so}" ]]; then
  echo "==> hardened_malloc: make produced no .so" >&2
  exit 1
fi
mkdir -p "${DEST}/usr/lib" "${DEST}/etc/cicada"
cp -a "${so}" "${DEST}/usr/lib/libhardened_malloc.so"
echo "${TAG}" > "${DEST}/etc/cicada/hardened_malloc.version"
echo "==> installed libhardened_malloc.so (${TAG}) from ${so}"
