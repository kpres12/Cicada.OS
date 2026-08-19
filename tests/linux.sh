#!/usr/bin/env bash
# The Linux-only half of the suite, run in a privileged linux/amd64 container.
#
# Why this exists: "unverified" was doing too much work. Some claims genuinely
# need the Air — a chipset watchdog resetting, the kernel refusing a USB device,
# a LoRa radio carrying a packet. But others were only ever "needs a Linux
# kernel", and Docker has one. A ruleset that a grep says is default-deny and a
# ruleset the kernel *loaded* as default-deny are different facts, and only the
# second one protects anybody.
#
#   tests/linux.sh              everything
#   tests/linux.sh nftables     just that file
#
# Requires Docker. Skips cleanly without it, because the Mac-side suite must
# stay runnable on a plane.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${CICADA_LINUX_IMAGE:-archlinux:latest}"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "skip: docker is not available — Linux-only checks not run"
  exit 0
fi

# Each entry is <script>:<packages it needs>. Kept here rather than inside each
# script so one pacman transaction covers a run.
#
# --disable-sandbox is required and is not a shortcut: pacman 7 confines its
# download user with landlock+seccomp, and that fails to initialise under
# qemu-user emulation ("error restricting syscalls via seccomp: 22"). Without
# it every install fails silently and the suite runs against whatever the base
# image happens to ship — which is how these tests spent their first run
# reporting a pass for a program that was not installed.
CASES=(
  "nftables:nftables iproute2 iputils python"
  "time-tor:chrony tor iproute2 curl"
  "duress:coreutils"
)

want="${1:-}"
rc=0
for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  pkgs="${entry#*:}"
  [[ -n "${want}" && "${want}" != "${name}" ]] && continue
  echo "=== linux/${name} ==="
  if ! docker run --rm --privileged --platform linux/amd64 \
        -v "${ROOT}:/src:ro" "${IMAGE}" \
        bash -c "pacman -Sy --noconfirm --quiet --disable-sandbox ${pkgs} >/tmp/pac.log 2>&1 \
                 || { echo '  FAIL pacman could not install: ${pkgs}'; tail -3 /tmp/pac.log; exit 1; }
             bash /src/tests/linux/${name}.sh"
  then
    rc=1
  fi
  echo
done

[[ "${rc}" -eq 0 ]] || { echo "LINUX TESTS FAILED"; exit 1; }
echo "linux ok"
