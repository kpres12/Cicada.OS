#!/usr/bin/env bash
# cicada-install's refusals on the dual-boot path.
#
# This is the code that decides whether to write to somebody's disk while
# another operating system is still on it, so what matters is not that it
# installs — it is everything it declines to touch, and that it declines for the
# RIGHT reason. A guard test that accepts any non-zero exit is a test of nothing:
# it passes just as happily when the installer fails because a helper is missing.
#
# Real loop partitions were the first attempt and they are not dependable here —
# Docker Desktop's VM does not always create /dev/loopNpX, and when it does it
# does not report a parent disk, which is the lookup every refusal below sits
# behind. So the block layer is modelled instead: mknod for device nodes (which
# is all `[[ -b ]]` needs) and stubs for lsblk/findmnt, which is where every
# fact cicada-install uses actually comes from. Deterministic, and it exercises
# the accept case too.
set -uo pipefail
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }
SRC=/src
INSTALL="${SRC}/packages/cicada-install/files/usr/local/bin/cicada-install"

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
dev="${tmp}/dev"; mkdir -p "${dev}"
stub="${tmp}/stub"; mkdir -p "${stub}"

# Fake block devices. Unbacked is fine: nothing reads them, and the destructive
# path is never reached because every case ends at --dry-run or a refusal.
n=200
for name in disk disk1 disk2 disk3 loose; do
  mknod "${dev}/${name}" b 7 "${n}" 2>/dev/null || { echo "  SKIP cannot mknod (need --privileged)"; exit 0; }
  n=$((n + 1))
done
DISK="${dev}/disk"; ESP="${dev}/disk1"; WIN="${dev}/disk2"; FREE="${dev}/disk3"; LOOSE="${dev}/loose"

# The model: disk1 = vfat ESP, disk2 = an installed OS (ntfs), disk3 = free space.
cat > "${stub}/lsblk" <<STUB
#!/usr/bin/env bash
dev="\${@: -1}"; base="\$(basename "\${dev}")"
has() { local want="\$1"; shift; [[ " \$* " == *" \${want} "* ]]; }
case "\${base}" in
  disk)  pk="";     fs="";     sz=\$((80 * 1024 * 1024 * 1024)); model="VENDOR SSD" ;;
  disk1) pk="disk"; fs="vfat"; sz=\$((512 * 1024 * 1024));       model="VENDOR SSD" ;;
  disk2) pk="disk"; fs="ntfs"; sz=\$((40 * 1024 * 1024 * 1024)); model="VENDOR SSD" ;;
  disk3) pk="disk"; fs="";     sz=\$((40 * 1024 * 1024 * 1024)); model="VENDOR SSD" ;;
  loose) pk="";     fs="ext4"; sz=\$((40 * 1024 * 1024 * 1024)); model="VENDOR SSD" ;;
  *)     pk="";     fs="";     sz=0; model="" ;;
esac
if has PKNAME "\$@"; then echo "\${pk}"
elif has FSTYPE "\$@"; then echo "\${fs}"
elif has MODEL "\$@"; then echo "\${model}"
elif has SIZE "\$@"; then echo "\${sz}"
else echo "\${base} \$((sz / 1024 / 1024 / 1024))G"; fi
exit 0
STUB
# Nothing is mounted unless a case says so via CICADA_TEST_MOUNTED.
cat > "${stub}/findmnt" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do
  if [[ "${a}" == "${CICADA_TEST_MOUNTED:-__none__}" ]]; then echo "/mnt/windows"; exit 0; fi
done
exit 1
STUB
# Not an Apple machine, and no live USB, unless a case overrides.
mkdir -p "${tmp}/dmi"
for c in lsblk findmnt; do chmod 755 "${stub}/${c}"; done
export PATH="${stub}:${PATH}"

pf="${tmp}/pw"; printf 'correct horse battery staple with plenty of words' > "${pf}"
uf="${tmp}/up"; printf 'userpassword123' > "${uf}"
run() { bash "${INSTALL}" --yes --dry-run --luks-pass-file "${pf}" --user-pass-file "${uf}" "$@" 2>&1; }

echo "==> the dual-boot path is accepted on a disk that already has an OS"
out="$(run --partition "${FREE}" --esp "${ESP}")"
if grep -q "NOT repartition" <<<"${out}"; then
  say "accepted the free partition and states it will not repartition the disk"
else
  die "partition mode rejected or mis-reported: ${out}"
fi
grep -q "will NOT be formatted" <<<"${out}" \
  && say "says out loud that the shared ESP is not formatted" \
  || die "no statement that the existing ESP is preserved"

echo "==> it refuses, and for the stated reason"
check_refuses() {
  local why="$1" expect="$2"; shift 2
  local o rc
  o="$(run "$@")"; rc=$?
  if [[ ${rc} -eq 0 ]]; then
    die "ACCEPTED what it must refuse (${why})"
  elif grep -qi -- "${expect}" <<<"${o}"; then
    say "refuses ${why}"
  else
    die "refused ${why} but for the WRONG reason — wanted /${expect}/, got: ${o}"
  fi
}
check_refuses "an --esp that is not vfat (formatting it would destroy the other OS)" \
  "not vfat" --partition "${FREE}" --esp "${WIN}"
check_refuses "--partition without --esp"        "go together"        --partition "${FREE}"
check_refuses "--esp without --partition"        "go together"        --esp "${ESP}"
check_refuses "--target and --partition together" "Pick one"          --partition "${FREE}" --esp "${ESP}" --target "${DISK}"
check_refuses "a whole disk where a partition belongs" "not a partition" --partition "${DISK}" --esp "${ESP}"
check_refuses "a device with no parent disk"     "not a partition"    --partition "${LOOSE}" --esp "${ESP}"
check_refuses "--partition and --esp being the same device" "cannot be the same" --partition "${ESP}" --esp "${ESP}"
check_refuses "a partition too small to install into" "need >=" --partition "${ESP}" --esp "${WIN}"

echo "==> a mounted target is in use and must not be written"
CICADA_TEST_MOUNTED="${FREE}" check_refuses "a mounted target partition" "mounted" \
  --partition "${FREE}" --esp "${ESP}"

echo "==> the whole-disk path still refuses what it always refused"
check_refuses "a nonexistent device" "not a block device" --target "${dev}/nope"

[[ "${fail}" -eq 0 ]] || { echo "INSTALL-GUARDS FAILED"; exit 1; }
echo "install-guards ok"
