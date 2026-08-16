#!/usr/bin/env bash
# Prove the UKI path does the one thing that keeps it from bricking laptops:
# it removes the unsigned type-1 fallback entries ONLY when every unified kernel
# image was built and verified. Everything else here is secondary.
#
# No root, no ukify, no kernel. A stub ukify stands in for the real one so we can
# make it succeed, fail, or emit a truncated image on demand, and then check what
# cicada-uki did to the ESP. This is the same shape as tests/luks-max-fail.sh:
# run the shipping code, stub only the peripherals.
#
# Run: tests/uki.sh   (also from tests/here.sh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

UKI="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-uki"
CHROOT="${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh"
HOOK="${ROOT}/packages/cicada-defaults/files/etc/pacman.d/hooks/zy-cicada-uki.hook"
SBHOOK="${ROOT}/packages/cicada-defaults/files/etc/pacman.d/hooks/zz-cicada-sbctl.hook"
TPM="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-tpm-enroll"
HW="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-hw-trust"

test -x "${UKI}" || die "cicada-uki is not executable"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# --- fake machine ------------------------------------------------------------

mkroot() {
  rm -rf "${tmp}/root"
  local m="${tmp}/root/modules" b="${tmp}/root/boot" e="${tmp}/root/esp"
  mkdir -p "${m}/6.9.1-hardened" "${m}/6.9.1-arch" "${b}" "${e}/loader/entries" "${tmp}/root/etc"
  echo linux-hardened > "${m}/6.9.1-hardened/pkgbase"
  echo linux          > "${m}/6.9.1-arch/pkgbase"
  : > "${m}/6.9.1-hardened/vmlinuz"
  : > "${m}/6.9.1-arch/vmlinuz"
  : > "${b}/initramfs-linux-hardened.img"
  : > "${b}/initramfs-linux.img"
  printf 'cryptdevice=UUID=dead-beef:cicada root=UUID=cafe-f00d rw quiet\n' \
    > "${tmp}/root/etc/cmdline"
  printf 'HOOKS=(base udev autodetect microcode modconf block cicada-crypt filesystems fsck)\n' \
    > "${tmp}/root/etc/mkinitcpio.conf"
  printf 'NAME="Cicada.OS"\nID=cicada\n' > "${tmp}/root/etc/os-release"
  printf 'default cicada.conf\ntimeout 3\n' > "${e}/loader/loader.conf"
  printf 'title Cicada.OS\nlinux /vmlinuz-linux-hardened\noptions x\n' \
    > "${e}/loader/entries/cicada.conf"
  printf 'title Cicada.OS (Wi-Fi)\nlinux /vmlinuz-linux\noptions x\n' \
    > "${e}/loader/entries/cicada-wifi.conf"
}

# MODE=ok      write a plausible 2 MiB PE
# MODE=fail    exit non-zero
# MODE=short   write a 10-byte "PE" (the truncated-image case)
# MODE=nonpe   write 2 MiB that does not start with MZ
# MODE=failone fail only for linux-hardened, succeed for the rest
mkstub() {
  mkdir -p "${tmp}/bin"
  cat > "${tmp}/bin/ukify" <<'STUB'
#!/usr/bin/env bash
# Stub ukify. Records argv so the test can assert on the baked cmdline.
mode="${UKIFY_MODE:-ok}"
if [[ "${1:-}" == "inspect" ]]; then
  printf '.linux\n.initrd\n.cmdline\n.osrel\n'
  exit 0
fi
out=""; cmdline=""
for a in "$@"; do
  case "${a}" in
    --output=*)  out="${a#--output=}" ;;
    --cmdline=*) cmdline="${a#--cmdline=}" ;;
  esac
done
printf '%s\n' "$*" >> "${UKIFY_LOG:-/dev/null}"
[[ "${mode}" == "fail" ]] && exit 1
if [[ "${mode}" == "failone" && "${cmdline}" == *lockdown* ]]; then
  exit 1
fi
case "${mode}" in
  short) printf 'MZshort' > "${out}" ;;
  nonpe) dd if=/dev/zero of="${out}" bs=1024 count=2048 2>/dev/null ;;
  *)     { printf 'MZ'; dd if=/dev/zero bs=1024 count=2048 2>/dev/null; } > "${out}" ;;
esac
exit 0
STUB
  chmod +x "${tmp}/bin/ukify"
}

run_uki() {
  local mode="$1"; shift
  UKIFY_MODE="${mode}" \
  UKIFY_LOG="${tmp}/ukify.log" \
  PATH="${tmp}/bin:${PATH}" \
  CICADA_UKI_ASSUME_ROOT=1 \
  CICADA_ESP="${tmp}/root/esp" \
  CICADA_MODULES_DIR="${tmp}/root/modules" \
  CICADA_BOOTDIR="${tmp}/root/boot" \
  CICADA_CMDLINE_FILE="${tmp}/root/etc/cmdline" \
  CICADA_MKINITCPIO_CONF="${tmp}/root/etc/mkinitcpio.conf" \
  CICADA_OS_RELEASE="${tmp}/root/etc/os-release" \
  bash "${UKI}" "$@"
}

entries_left() { ls "${tmp}/root/esp/loader/entries"/*.conf 2>/dev/null | wc -l | tr -d ' '; }
ukis_built()   { ls "${tmp}/root/esp/EFI/Linux"/*.efi 2>/dev/null | wc -l | tr -d ' '; }

mkstub

echo "==> happy path: every UKI builds, fallback entries retire"
mkroot
: > "${tmp}/ukify.log"
run_uki ok build >/dev/null 2>&1 || die "build failed on the happy path"
[[ "$(ukis_built)" == "2" ]] || die "expected 2 UKIs, got $(ukis_built)"
test -f "${tmp}/root/esp/EFI/Linux/cicada-linux-hardened.efi" || die "no hardened UKI"
test -f "${tmp}/root/esp/EFI/Linux/cicada-linux.efi" || die "no stock UKI"
[[ "$(entries_left)" == "0" ]] || die "type-1 entries survived a fully successful build"
grep -q '^default cicada-linux-hardened.efi$' "${tmp}/root/esp/loader/loader.conf" \
  || die "loader.conf default was not pointed at the hardened UKI"
say "2 UKIs built + verified, 2 unsigned entries removed, default repointed"

echo "==> the cmdline actually gets baked, and only hardened gets lockdown"
grep -q 'cryptdevice=UUID=dead-beef:cicada' "${tmp}/ukify.log" \
  || die "the installed cmdline never reached ukify"
[[ "$(grep -c 'lockdown=confidentiality' "${tmp}/ukify.log")" == "1" ]] \
  || die "lockdown=confidentiality must be on exactly one kernel (hardened), not both"
grep -q 'lockdown' <<<"$(grep 'initramfs-linux-hardened' "${tmp}/ukify.log")" \
  || die "lockdown landed on the wrong kernel"
# A Wi-Fi rescue entry that cannot load out-of-tree wl is not a rescue entry.
grep 'initramfs-linux.img' "${tmp}/ukify.log" | grep -q 'lockdown' \
  && die "stock/Wi-Fi kernel must NOT carry lockdown (blocks Broadcom wl)" || true
say "cmdline baked from /etc/kernel/cmdline; lockdown only on linux-hardened"

echo "==> a failed build must leave the machine bootable"
mkroot
run_uki fail build >/dev/null 2>&1 && die "build reported success when ukify always failed" || true
[[ "$(entries_left)" == "2" ]] || die "type-1 entries were removed after a total build failure — machine would not boot"
[[ "$(ukis_built)" == "0" ]] || die "a failed ukify left an artefact behind"
say "total failure: entries kept, no half-written UKI"

echo "==> a PARTIAL failure must also leave the fallback in place"
mkroot
run_uki failone build >/dev/null 2>&1 || true
[[ "$(ukis_built)" == "1" ]] || die "expected exactly 1 UKI from the partial run, got $(ukis_built)"
[[ "$(entries_left)" == "2" ]] || die "one kernel had no UKI but the fallback entries were still deleted"
say "1 of 2 built: entries kept until every kernel is covered"

echo "==> verification rejects an image that ukify was happy with"
for mode in short nonpe; do
  mkroot
  run_uki "${mode}" build >/dev/null 2>&1 && die "build accepted a ${mode} image" || true
  [[ "$(ukis_built)" == "0" ]] || die "${mode}: a bad image was left on the ESP"
  [[ "$(entries_left)" == "2" ]] || die "${mode}: fallback entries removed despite a bad image"
done
say "truncated and non-PE images rejected, ESP left clean"

echo "==> no ukify at all is a refusal, not a silent downgrade"
mkroot
set +e
PATH="/usr/bin:/bin" CICADA_UKI_ASSUME_ROOT=1 \
  CICADA_ESP="${tmp}/root/esp" CICADA_MODULES_DIR="${tmp}/root/modules" \
  CICADA_BOOTDIR="${tmp}/root/boot" CICADA_CMDLINE_FILE="${tmp}/root/etc/cmdline" \
  bash "${UKI}" build >"${tmp}/noukify.out" 2>&1
rc=$?
set -e
[[ "${rc}" == "2" ]] || die "missing ukify should exit 2, got ${rc}"
grep -q 'NOT covered by Secure Boot' "${tmp}/noukify.out" \
  || die "missing ukify must say what is now unprotected"
[[ "$(entries_left)" == "2" ]] || die "entries removed even though no UKI was built"
say "exit 2, explains the exposure, leaves the machine bootable"

echo "==> stale UKIs for uninstalled kernels are pruned"
mkroot
mkdir -p "${tmp}/root/esp/EFI/Linux"
{ printf 'MZ'; dd if=/dev/zero bs=1024 count=2048 2>/dev/null; } \
  > "${tmp}/root/esp/EFI/Linux/cicada-linux-lts.efi"
run_uki ok build >/dev/null 2>&1 || die "build failed with a stale UKI present"
test -f "${tmp}/root/esp/EFI/Linux/cicada-linux-lts.efi" \
  && die "a signed UKI for an uninstalled kernel is still bootable — must be pruned" || true
say "cicada-linux-lts.efi pruned when its kernel is gone"

echo "==> status names the thing that actually matters"
mkroot
run_uki ok status > "${tmp}/status.out" 2>&1 || die "status exited non-zero on a fresh machine"
grep -q 'no UKI' "${tmp}/status.out" || die "status does not flag a machine with no signed boot image"
run_uki ok build >/dev/null 2>&1 || die "build failed before status check"
# Put one unsigned entry back by hand: a leftover type-1 is the interesting
# state, because it is an editable cmdline one menu keypress from the signed one.
printf 'title stale\n' > "${tmp}/root/esp/loader/entries/cicada.conf"
run_uki ok status > "${tmp}/status2.out" 2>&1 || die "status exited non-zero"
grep -q 'still bootable' "${tmp}/status2.out" \
  || die "status does not warn that an unsigned entry is still bootable"
grep -q 'cicada-linux-hardened.efi' "${tmp}/status2.out" || die "status does not list the UKIs"
say "status flags 'no UKI' and 'unsigned entry still bootable'"

echo "==> restore is a real way back"
mkroot
run_uki ok build >/dev/null 2>&1 || die "build failed before restore test"
[[ "$(entries_left)" == "0" ]] || die "precondition: entries should be gone"
run_uki ok restore >/dev/null 2>&1 || die "restore failed"
[[ "$(entries_left)" == "2" ]] || die "restore did not rebuild both entries"
grep -q 'cryptdevice=UUID=dead-beef' "${tmp}/root/esp/loader/entries/cicada.conf" \
  || die "restored entry lost the cmdline"
grep -q 'lockdown=confidentiality' "${tmp}/root/esp/loader/entries/cicada.conf" \
  || die "restored hardened entry lost lockdown"
say "restore rebuilds both entries with the right cmdline"

# --- wiring (the harness cannot see these) -----------------------------------

echo "==> wiring: install, hooks, and the tier claim"
grep -q '/etc/kernel/cmdline' "${CHROOT}" \
  || die "install-chroot must write /etc/kernel/cmdline — a UKI has nowhere else to read it from"
grep -q 'cicada-uki build' "${CHROOT}" || die "install never builds a UKI"
# Order matters: the type-1 entries must be written BEFORE the UKI attempt, or a
# failed build leaves a machine with no boot entries at all.
python3 - <<PY || die "install builds the UKI before writing the fallback entries"
import pathlib, sys
t = pathlib.Path("${CHROOT}").read_text()
sys.exit(0 if t.index("loader/entries/cicada.conf") < t.index("cicada-uki build") else 1)
PY

test -f "${HOOK}" || die "no pacman hook: a kernel upgrade would leave a stale UKI signed and bootable"
grep -q 'cicada-uki build' "${HOOK}" || die "uki hook does not rebuild"
grep -q 'usr/lib/modules/\*/vmlinuz' "${HOOK}" || die "uki hook does not trigger on kernel upgrade"
# Filename ordering is load-bearing: mkinitcpio (90-) then uki (zy-) then sbctl (zz-).
[[ "$(basename "${HOOK}")" < "$(basename "${SBHOOK}")" ]] \
  || die "uki hook must sort before the sbctl hook or the new image is signed stale"
say "install writes cmdline + builds UKI after the fallback; hook ordering correct"

echo "==> PCR 11 is only claimed when a UKI actually measured"
grep -q 'uki_measured' "${TPM}" || die "tpm-enroll must check PCR 11, not just look for files on the ESP"
grep -q 'pcr-sha256/11' "${TPM}" || die "tpm-enroll does not read PCR 11"
grep -q '0+7+11' "${TPM}" || die "tpm-enroll lost the UKI PCR set"
# Sealing to an all-zero PCR 11 binds the disk to "booted WITHOUT a UKI", which
# is the state we are trying to make unbootable.
grep -q 'PCR 11 is empty' "${TPM}" || die "tpm-enroll must explain why it fell back to 0+7"
grep -q 'pcr-sha256/11' "${HW}" || die "hw-trust still claims Tier 2 from a directory listing"
say "Tier 2 requires a measured UKI, not an EFI/Linux directory"

if [[ "${fail}" -ne 0 ]]; then
  echo "UKI FAILED"
  exit 1
fi
echo "UKI OK"
