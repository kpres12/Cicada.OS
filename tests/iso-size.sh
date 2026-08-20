#!/usr/bin/env bash
# Does the built ISO still fit in a single GitHub release asset?
#
# This is a release-blocking property, not a nicety. Above 2 GiB the image has to
# ship as .part-00/.part-01, and reassembling them with `cat` becomes step one of
# every install — before the user can even flash. That is the highest-attrition
# step in the whole funnel, and it is invisible from the source tree: nothing in
# a diff tells you the image just crossed the line.
#
# The image went 1.9 -> 2.9 GiB once already, over several commits, and nobody
# noticed until a release had to be split. A kernel bump alone moves it ~10 MiB.
#
# Run after a build:  tests/iso-size.sh [path/to.iso]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# GitHub rejects a release asset over 2 GiB. Not 2 GB, not "about 2 gigs".
CAP=$((2 * 1024 * 1024 * 1024))
# Below this much headroom, a single kernel or firmware bump can push a release
# over without anyone touching the package list. Warn while it is still cheap.
WARN_MIB="${CICADA_ISO_WARN_MIB:-80}"

iso="${1:-}"
if [[ -z "${iso}" ]]; then
  iso="$(ls -1t "${ROOT}"/out/cicada-*.iso 2>/dev/null | grep -v 'cicada-latest' | head -1 || true)"
fi
if [[ -z "${iso}" || ! -f "${iso}" ]]; then
  echo "skip: no ISO in out/ — build one first (scripts/build-iso-docker.sh)"
  exit 0
fi

# stat is not portable between macOS and Linux, and this suite runs on both.
if size="$(stat -f%z "${iso}" 2>/dev/null)"; then :; else size="$(stat -c%s "${iso}")"; fi

mib() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1048576}'; }
gib() { awk -v b="$1" 'BEGIN{printf "%.3f", b/1073741824}'; }

echo "==> $(basename "${iso}")"
echo "    size    $(gib "${size}") GiB (${size} bytes)"
echo "    cap     2.000 GiB (GitHub release asset limit)"

if (( size > CAP )); then
  over=$(( size - CAP ))
  echo "    FAIL    over by $(mib "${over}") MiB — this release would have to ship as .part-* files"
  echo
  echo "Where the space goes, and what has been tried (see iso/packages.exclude):"
  echo "  - squashfs compression is already maximal: mksquashfs caps blocks at"
  echo "    1 MiB and the xz dictionary cannot exceed the block size, so there is"
  echo "    no tuning headroom. Space has to come out of content."
  echo "  - the kernel and initramfs are written TWICE (ISO 9660 + the embedded"
  echo "    efiboot.img), so every MiB removed from the initramfs saves two."
  echo "  - CICADA_SLIM_INITRAMFS=1 drops the kms hook: ~96 MiB, at the cost of"
  echo "    early modesetting. Boot-test it before making it the default."
  exit 1
fi

head=$(( CAP - size ))
echo "    OK      $(mib "${head}") MiB of headroom — ships as one file"
head_mib="$(awk -v b="${head}" 'BEGIN{printf "%d", b/1048576}')"
if (( head_mib < WARN_MIB )); then
  echo
  echo "    WARN    under ${WARN_MIB} MiB of headroom. A kernel or firmware bump"
  echo "            can cross the cap without any change to the package list."
  echo "            CICADA_SLIM_INITRAMFS=1 buys back ~96 MiB when you need it."
fi
exit 0
