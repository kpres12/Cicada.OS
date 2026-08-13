#!/usr/bin/env bash
# Prove the amnesic live path is wired, then print (or run) the bulk_extractor
# check that the USB never stored a session canary.
#
# Mac / builder (no Air):  ./tests/amnesic-verify.sh
# After an Air session:    CICADA_BE_DEV=/dev/rdisk4 ./tests/amnesic-verify.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

echo "==> Part 1 bugs must stay fixed"
am="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-amnesic"
watch="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-yank-watch"
panic="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-panic"

grep -q 'RUN+=' "${am}" && die "udev RUN+ is back in cicada-amnesic" || say "no udev RUN+systemctl"
grep -qE 'udevadm trigger$' "${am}" && die "bare udevadm trigger (false-panic at boot)" || true
grep -q 'udevadm trigger --subsystem-match=block --action=change' "${am}" \
  || die "amnesic must reload block devices with change, not a global trigger"
grep -q 'KERNEL=="%sp*"' "${am}" || die "UDISKS_IGNORE missing nvme partitions"
grep -q 'KERNEL=="%s[0-9]*"' "${am}" || die "UDISKS_IGNORE missing sda partitions"
say "internal-disk ignore covers partitions"

test -x "${watch}" || die "cicada-yank-watch not executable"
grep -q 'cicada-panic' "${watch}" || die "yank-watch does not exec panic"
grep -q 'copytoram already released' "${watch}" || die "yank-watch must not arm if UUID never appears"
grep -q 'reboot --force' "${panic}" || die "panic is not force-reboot"
say "yank watcher + force reboot"

test -f "${ROOT}/packages/cicada-defaults/files/etc/systemd/system/cicada-yank-watch.service" \
  || die "yank-watch unit missing"
grep -q 'cicada-yank-watch.service' "${ROOT}/iso/assemble-profile.sh" \
  || die "assemble does not enable yank-watch"

echo "==> boot entries (assemble if needed)"
P="${CICADA_PROFILE_DIR:-}"
if [[ -z "${P}" || ! -d "${P}/efiboot/loader/entries" ]]; then
  P="$(mktemp -d)"
  export CICADA_PROFILE_DIR="${P}"
  bash "${ROOT}/iso/assemble-profile.sh" >/tmp/cicada-amnesic-assemble.log 2>&1 || {
    tail -20 /tmp/cicada-amnesic-assemble.log
    die "assemble"
    P=""
  }
fi
if [[ -n "${P}" && -d "${P}/efiboot/loader/entries" ]]; then
  test -f "${P}/efiboot/loader/entries/04-cicada-amnesic.conf" || die "04-cicada-amnesic.conf missing"
  grep -q copytoram "${P}/efiboot/loader/entries/04-cicada-amnesic.conf" || die "amnesic entry lacks copytoram"
  def=$(echo "${P}/efiboot/loader/entries/"01-*.conf)
  grep -q copytoram "${def}" && die "default live is copytoram" || say "default live keeps USB (8GB Air)"
  test -L "${P}/airootfs/etc/systemd/system/multi-user.target.wants/cicada-yank-watch.service" \
    || die "yank-watch not enabled in live tree"
  test -x "${P}/airootfs/usr/local/bin/cicada-yank-watch" || die "yank-watch not 755 in profile"
  grep -q 'init_on_free=1' "${def}" || die "default live missing init_on_free"
  say "assembled amnesic entry + units"
fi

echo "==> bulk_extractor procedure (USB must not keep the session)"
CANARY_PREFIX="CICADA-CANARY"
cat <<'PROC'
  On the Air (amnesic boot entry):
    1. Pick "Cicada.OS live (amnesic — copy to RAM)".
    2. CANARY="CICADA-CANARY-$(head -c 8 /dev/urandom | xxd -p)"
       echo "$CANARY" | tee /tmp/canary.txt ~/CANARY.txt
       # optional: paste it into a kitty window so it sits in RAM
    3. Write the exact string down on paper. Do not save it to the live USB.
    4. Reboot (or yank — panic reboot). Do not "persist" anything.

  On this Mac, stick back in (read-only):
    export CICADA_BE_DEV=/dev/rdisk4          # confirm with diskutil list
    export CICADA_CANARY='CICADA-CANARY-....' # the paper string
    ./tests/amnesic-verify.sh

  Pass = bulk_extractor (or strings) finds zero hits for CICADA_CANARY on the stick.
  That is overlay-in-RAM, not Tails sdmem. RAM cold-boot is still in the threat model.
PROC

if [[ -n "${CICADA_BE_DEV:-}" ]]; then
  [[ -n "${CICADA_CANARY:-}" ]] || die "set CICADA_CANARY to the paper string"
  [[ "${CICADA_CANARY}" == ${CANARY_PREFIX}* ]] || die "CICADA_CANARY must start with ${CANARY_PREFIX}"
  if [[ ! -e "${CICADA_BE_DEV}" ]]; then
    die "CICADA_BE_DEV ${CICADA_BE_DEV} not present"
  else
    out="$(mktemp -d)"
    if command -v bulk_extractor >/dev/null 2>&1; then
      bulk_extractor -o "${out}/be" "${CICADA_BE_DEV}"
      if grep -R -- "${CICADA_CANARY}" "${out}/be" >/dev/null 2>&1; then
        die "canary found on ${CICADA_BE_DEV} — live USB stored session data"
      else
        say "bulk_extractor: no canary on ${CICADA_BE_DEV}"
      fi
    else
      echo "  (bulk_extractor not installed; strings fallback)"
      if strings "${CICADA_BE_DEV}" | grep -F -- "${CICADA_CANARY}" >/dev/null 2>&1; then
        die "canary found on ${CICADA_BE_DEV} via strings"
      else
        say "strings: no canary on ${CICADA_BE_DEV}"
      fi
    fi
    rm -rf "${out}"
  fi
else
  say "skip disk scan (set CICADA_BE_DEV + CICADA_CANARY after an Air session)"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "AMNESIC-VERIFY FAILED"
  exit 1
fi
echo "AMNESIC-VERIFY OK"
