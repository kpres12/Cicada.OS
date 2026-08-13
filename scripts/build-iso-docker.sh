#!/usr/bin/env bash
# Build the Intel/x86_64 Cicada ISO from macOS (Apple Silicon) via Docker.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${CICADA_ISO_IMAGE:-cicada-iso-builder:latest}"
FULL="${CICADA_FULL:-0}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found. Install Docker Desktop and enable Rosetta/amd64 emulation." >&2
  exit 1
fi

mkdir -p "${ROOT}/out"

echo "==> building linux/amd64 builder image (Arch + archiso)"
docker build \
  --platform linux/amd64 \
  -f "${ROOT}/Dockerfile.build" \
  -t "${IMAGE}" \
  "${ROOT}"

echo "==> running mkarchiso (privileged, work dir on Linux VM volume — not macOS bind-mount)"
echo "    first run downloads the Arch bootstrap; on M2 this is emulated x86_64 and can take a while."

exec docker run --rm \
  --platform linux/amd64 \
  --privileged \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -e CICADA_FULL="${FULL}" \
  -e CICADA_OUT=/out \
  -e CICADA_WORK=/work \
  -e CICADA_SRC=/src \
  -v "${ROOT}:/src:ro" \
  -v cicada-iso-work:/work \
  -v cicada-pacman-cache:/var/cache/pacman/pkg \
  -v "${ROOT}/out:/out" \
  "${IMAGE}"
