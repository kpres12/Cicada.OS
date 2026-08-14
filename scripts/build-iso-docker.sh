#!/usr/bin/env bash
# Build the Intel/x86_64 Cicada ISO from macOS (Apple Silicon) via Docker.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${CICADA_ISO_IMAGE:-cicada-iso-builder:latest}"
FULL="${CICADA_FULL:-0}"
WORK_VOL="${CICADA_ISO_WORK_VOL:-cicada-iso-work}"
PKG_VOL="${CICADA_ISO_PKG_VOL:-cicada-pacman-cache}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found. Install Docker Desktop and enable Rosetta/amd64 emulation." >&2
  exit 1
fi

mkdir -p "${ROOT}/out"

# One builder at a time. Parallel/killed runs corrupt pacstrap under qemu
# (perl desc missing → transaction aborted) when they share cicada-iso-work.
echo "==> stopping any prior cicada ISO builders"
docker ps -q --filter "ancestor=${IMAGE}" | xargs -r docker kill >/dev/null 2>&1 || true
# Also match by name pattern from older runs
docker ps -aq --filter "volume=${WORK_VOL}" | while read -r id; do
  img="$(docker inspect -f '{{.Config.Image}}' "${id}" 2>/dev/null || true)"
  case "${img}" in
    *cicada-iso*) docker kill "${id}" >/dev/null 2>&1 || true ;;
  esac
done

echo "==> scrubbing stale mkarchiso work on ${WORK_VOL}"
# Leftover half-installed airootfs from a killed pacstrap is what blew up perl's
# local/desc. Always wipe mkarchiso + profile before a fresh assemble.
docker volume create "${WORK_VOL}" >/dev/null
docker volume create "${PKG_VOL}" >/dev/null
docker run --rm \
  --platform linux/amd64 \
  -v "${WORK_VOL}:/work" \
  archlinux:latest \
  bash -c 'rm -rf /work/mkarchiso /work/profile; mkdir -p /work; df -h /work' \
  || {
    # archlinux pull can fail offline; alpine is enough to rm -rf
    docker run --rm -v "${WORK_VOL}:/work" alpine:3.20 \
      sh -c 'rm -rf /work/mkarchiso /work/profile; mkdir -p /work'
  }

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
  --name "cicada-iso-build-$$" \
  -e CICADA_FULL="${FULL}" \
  -e CICADA_OUT=/out \
  -e CICADA_WORK=/work \
  -e CICADA_SRC=/src \
  -v "${ROOT}:/src:ro" \
  -v "${WORK_VOL}:/work" \
  -v "${PKG_VOL}:/var/cache/pacman/pkg" \
  -v "${ROOT}/out:/out" \
  "${IMAGE}"
