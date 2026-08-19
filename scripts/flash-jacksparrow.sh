#!/usr/bin/env bash
# Flash the newest Cicada ISO to the external USB stick.
# Run in Terminal.app — needs your Mac password for dd.
#
# The target is DISCOVERED, not hardcoded. A disk number is not an identity:
# /dev/disk4 was this stick on one boot and a mounted ProtonPass disk image on
# the next, and a script that dd's to a number is a script that eventually dd's
# to the wrong thing. Everything below picks a disk by what it *is* — external,
# physical, whole, removable — and refuses rather than guesses when that does
# not resolve to exactly one answer.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-${ROOT}/out/cicada-latest-x86_64.iso}"

die() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || die "this script is macOS/diskutil only"
[[ -f "${ISO}" ]] || die "no ISO at ${ISO} (build one: ./scripts/build-iso-docker.sh)"

echo "==> ISO: ${ISO}"
ls -lh "${ISO}"
REAL="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${ISO}")"
echo "==> real: ${REAL}"
shasum -a 256 "${REAL}"

# Flashing a stale image is how a fixed bug gets re-reported, so say what is on
# this one before erasing a disk for it. build-iso-docker.sh writes the ISO's
# own BUILD-ID beside it, because the authoritative copy is inside the squashfs
# and unreadable here without mounting the image.
ISO_COMMIT=""
if [[ -s "${REAL}.build-id" ]]; then
  echo "==> BUILD-ID (from the image):"
  sed 's/^/      /' "${REAL}.build-id"
  ISO_COMMIT="$(sed -n 's/^commit=//p' "${REAL}.build-id" | head -1)"
else
  echo "==> no BUILD-ID sidecar — this ISO predates the build script writing one."
  echo "    Falling back to timestamps, which is a guess, not a check."
  echo "    ISO built: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "${REAL}")"
fi

if command -v git >/dev/null 2>&1 && git -C "${ROOT}" rev-parse HEAD >/dev/null 2>&1; then
  head_commit="$(git -C "${ROOT}" rev-parse --short HEAD)"
  echo "==> tree now at: ${head_commit} $(git -C "${ROOT}" log -1 --format='%s')"
  if [[ -n "${ISO_COMMIT}" && "${ISO_COMMIT}" != "${head_commit}" ]]; then
    behind="$(git -C "${ROOT}" rev-list --count "${ISO_COMMIT}..HEAD" 2>/dev/null || echo '?')"
    echo "    NOTE: this image is ${behind} commit(s) behind the tree."
    echo "          Nothing committed since ${ISO_COMMIT} is on it."
  elif [[ -n "${ISO_COMMIT}" ]]; then
    echo "    This image matches the tree exactly."
  fi
fi

# --- target discovery --------------------------------------------------------
# One source of truth, read as a plist rather than scraped out of the
# human-readable table: diskutil's column layout is for people, and a script
# that parses it breaks quietly when Apple changes a heading.
_field() {
  # _field <disk> <plist key>
  diskutil info -plist "/dev/$1" 2>/dev/null \
    | plutil -extract "$2" raw -o - - 2>/dev/null || true
}

# Is this disk something we are willing to destroy? Every condition is a
# separate refusal, because "external" alone is not enough — a 4 TB backup drive
# is external too, and the previous version of this guard would have accepted it.
_is_flashable() {
  local d="$1"
  [[ "$(_field "${d}" Internal)" == "false" ]] || return 1
  [[ "$(_field "${d}" VirtualOrPhysical)" == "Physical" ]] || return 1
  [[ "$(_field "${d}" WholeDisk)" == "true" ]] || return 1
  [[ "$(_field "${d}" RemovableMedia)" == "true" ]] || return 1
  return 0
}

_describe() {
  local d="$1" name size
  name="$(_field "${d}" MediaName)"
  size="$(_field "${d}" IOKitSize)"
  printf '%s — %s (%s GB)' "${d}" "${name:-unknown}" "$(( ${size:-0} / 1000000000 ))"
}

if [[ -n "${CICADA_FLASH_DISK:-}" ]]; then
  # An explicit override still gets validated. Naming a disk is permission to
  # erase that disk, not permission to skip the checks that stop you erasing
  # your boot volume.
  DISK="${CICADA_FLASH_DISK#/dev/}"
  DISK="${DISK#r}"
  _is_flashable "${DISK}" \
    || die "CICADA_FLASH_DISK=${DISK} is not an external, physical, whole, removable disk.
       $(diskutil info "/dev/${DISK}" 2>/dev/null | sed -n 's/^ *\(Device \/ Media Name\|Internal\|Removable Media\):/  &/p')"
  echo "==> target from CICADA_FLASH_DISK: $(_describe "${DISK}")"
else
  candidates=()
  # `|| [[ -n "${d}" ]]` is not decoration: plutil emits its JSON with no
  # trailing newline, so a plain `while read` silently drops the last (and with
  # one stick attached, the only) candidate and this reports "no disk found"
  # while the disk is sitting right there.
  while read -r d || [[ -n "${d}" ]]; do
    [[ -n "${d}" ]] || continue
    _is_flashable "${d}" && candidates+=("${d}")
  done < <(diskutil list -plist external physical 2>/dev/null \
             | plutil -extract WholeDisks json -o - - 2>/dev/null \
             | tr -d '[]"' | tr ',' '\n')

  case "${#candidates[@]}" in
    0)
      die "no external removable disk found. Plug the stick in, then re-run.
       (diskutil list external physical)"
      ;;
    1)
      DISK="${candidates[0]}"
      echo "==> found one external removable disk: $(_describe "${DISK}")"
      ;;
    *)
      # Never pick for the user here. Two sticks plugged in is exactly the
      # moment a wrong guess is unrecoverable.
      echo "error: more than one external removable disk is attached:" >&2
      for d in "${candidates[@]}"; do echo "         $(_describe "${d}")" >&2; done
      die "refusing to choose. Re-run with: CICADA_FLASH_DISK=diskN $0"
      ;;
  esac
fi

# --- confirm -----------------------------------------------------------------
# Typed confirmation, not a 5-second Ctrl-C window: a countdown is a race that
# the person walking away from the keyboard loses, and this erases a disk.
# Same shape as `cicada-auth confirm`, which makes you type ALLOW.
echo
echo "==> THIS ERASES $(_describe "${DISK}") COMPLETELY."
diskutil list "/dev/${DISK}"
echo
if [[ -t 0 ]]; then
  answer=""
  # `|| true` so an EOF on stdin lands on the refusal below with a message,
  # instead of tripping `set -e` and exiting silently.
  read -r -p "Type ERASE to continue: " answer || true
  [[ "${answer}" == "ERASE" ]] || die "not confirmed — nothing was written"
else
  die "no TTY to confirm on. Run this in Terminal.app, not from a pipe."
fi

diskutil unmountDisk "/dev/${DISK}"
# rdisk = raw character device, much faster than the buffered block device
sudo dd if="${REAL}" of="/dev/r${DISK}" bs=4m status=progress
sync
diskutil eject "/dev/${DISK}"
echo "==> done. Boot the Air from it (hold Option at chime)."
