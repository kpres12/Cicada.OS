#!/usr/bin/env bash
# Build the Intel/x86_64 Cicada ISO from macOS (Apple Silicon) via Docker.
#
# One build at a time (flock). Never kills a healthy in-flight builder unless
# CICADA_ISO_FORCE=1 — that was the EXIT:137 / poisoned-work loop.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${CICADA_ISO_IMAGE:-cicada-iso-builder:latest}"
FULL="${CICADA_FULL:-0}"
WORK_VOL="${CICADA_ISO_WORK_VOL:-cicada-iso-work}"
PKG_VOL="${CICADA_ISO_PKG_VOL:-cicada-pacman-cache}"
FORCE="${CICADA_ISO_FORCE:-0}"
LOCK="${ROOT}/out/.cicada-iso-build.lock"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found. Install Docker Desktop and enable Rosetta/amd64 emulation." >&2
  exit 1
fi

mkdir -p "${ROOT}/out"

running_builders() {
  docker ps -q --filter "ancestor=${IMAGE}" 2>/dev/null || true
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null \
    | awk '/cicada-iso-build/ {print $1}' || true
}

# Hold the lock for the whole docker run (do not `exec` — that drops the flock).
exec 9>"${LOCK}"
if ! flock -n 9; then
  echo "error: another Cicada ISO build already holds ${LOCK}" >&2
  echo "       running containers:" >&2
  docker ps --filter "ancestor=${IMAGE}" --format '  {{.ID}} {{.Status}} {{.Names}}' >&2 || true
  echo "       wait for it, or: CICADA_ISO_FORCE=1 ./scripts/build-iso-docker.sh" >&2
  exit 1
fi

ids="$(running_builders | sort -u | tr '\n' ' ')"
if [[ -n "${ids// }" ]]; then
  if [[ "${FORCE}" != "1" ]]; then
    echo "error: cicada ISO builder already running: ${ids}" >&2
    echo "       refusing to kill (that was EXIT:137 / corrupt pacstrap)." >&2
    echo "       wait, or: CICADA_ISO_FORCE=1 ./scripts/build-iso-docker.sh" >&2
    exit 1
  fi
  echo "==> CICADA_ISO_FORCE=1 — stopping prior builders: ${ids}"
  # shellcheck disable=SC2086
  docker kill ${ids} >/dev/null 2>&1 || true
  sleep 2
fi

echo "==> scrubbing stale mkarchiso work on ${WORK_VOL}"
docker volume create "${WORK_VOL}" >/dev/null
docker volume create "${PKG_VOL}" >/dev/null
if ! docker run --rm \
  --platform linux/amd64 \
  -v "${WORK_VOL}:/work" \
  archlinux:latest \
  bash -c 'rm -rf /work/mkarchiso /work/profile; mkdir -p /work; df -h /work'
then
  docker run --rm -v "${WORK_VOL}:/work" alpine:3.20 \
    sh -c 'rm -rf /work/mkarchiso /work/profile; mkdir -p /work'
fi

echo "==> building linux/amd64 builder image (Arch + archiso)"
docker build \
  --platform linux/amd64 \
  -f "${ROOT}/Dockerfile.build" \
  -t "${IMAGE}" \
  "${ROOT}"

NAME="cicada-iso-build-$$"
echo "==> running mkarchiso as ${NAME} (privileged, Linux VM volume)"
echo "    log tip: docker logs -f ${NAME}"

# Line-buffered so squash progress / EXIT land in redirected logs.
docker run --rm \
  --platform linux/amd64 \
  --privileged \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --name "${NAME}" \
  -e CICADA_FULL="${FULL}" \
  -e CICADA_OUT=/out \
  -e CICADA_WORK=/work \
  -e CICADA_SRC=/src \
  -v "${ROOT}:/src:ro" \
  -v "${WORK_VOL}:/work" \
  -v "${PKG_VOL}:/var/cache/pacman/pkg" \
  -v "${ROOT}/out:/out" \
  "${IMAGE}"

echo "==> newest ISO:"
ls -lt "${ROOT}/out"/cicada-*.iso | head -5
if [[ -L "${ROOT}/out/cicada-latest-x86_64.iso" ]] || [[ -f "${ROOT}/out/cicada-latest-x86_64.iso" ]]; then
  ls -lh "${ROOT}/out/cicada-latest-x86_64.iso"
fi
