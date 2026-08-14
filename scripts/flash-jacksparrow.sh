#!/usr/bin/env bash
# Flash the newest Cicada ISO to JACKSPARROW (SanDisk ~250GB).
# Run in Terminal.app — needs your Mac password for dd.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-${ROOT}/out/cicada-latest-x86_64.iso}"

echo "==> ISO: ${ISO}"
ls -lh "${ISO}"
# Resolve symlink for hashing
REAL="$(python3 -c "import os; print(os.path.realpath('${ISO}'))")"
echo "==> real: ${REAL}"
shasum -a 256 "${REAL}"

echo
echo "==> external disks (confirm JACKSPARROW / SanDisk ~250GB):"
diskutil list external physical

DISK="${CICADA_FLASH_DISK:-disk4}"
# Sanity: must be external SanDisk-ish and ~250GB
info="$(diskutil info "/dev/${DISK}" 2>/dev/null || true)"
echo "${info}" | grep -qi 'SanDisk\|External' || {
  echo "error: /dev/${DISK} does not look like JACKSPARROW. Set CICADA_FLASH_DISK=diskN" >&2
  exit 1
}
size="$(echo "${info}" | awk -F: '/Disk Size/{print $2}' | head -1)"
echo "==> target /dev/${DISK} (${size})"
echo "==> THIS ERASES THE STICK. Ctrl-C within 5s to abort."
sleep 5

diskutil unmountDisk "/dev/${DISK}"
# rdisk = raw, much faster
sudo dd if="${REAL}" of="/dev/r${DISK}" bs=4m status=progress
sync
diskutil eject "/dev/${DISK}"
echo "==> done. Boot the Air from JACKSPARROW."
