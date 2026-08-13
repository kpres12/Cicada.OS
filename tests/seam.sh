#!/usr/bin/env bash
# The live/installed seam. Every bug found on the Air so far has lived here:
# something configured for one side and silently absent or wrong on the other.
# These checks are mechanical — they compare what the tree ships against what
# each side actually receives, so a new file cannot quietly reach only one.
#
# Run: tests/seam.sh   (also invoked from tests/here.sh)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

CHROOT="${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh"
ASSEMBLE="${ROOT}/iso/assemble-profile.sh"

echo "==> every /etc dir Cicada ships reaches an installed system"
# copy_product is a hardcoded allowlist. Anything shipped but not listed lands
# on the live ISO (assemble rsyncs wholesale) and nowhere else — the failure is
# invisible until someone installs to disk.
python3 - "${ROOT}" <<'PY' || fail=1
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
inst = (root / "packages/cicada-install/files/usr/local/bin/cicada-install").read_text()
allow = set(re.findall(r'^\s+(/etc/[\w./-]+)\s*\\?$', inst, re.M))
# Handled outside the loop by their own explicit rsync/cp/find.
# NB: "/etc" itself must NOT go in here — every path starts with "/etc/", so it
# would make the prefix test below match unconditionally and the whole check a
# no-op. Files sitting directly in /etc are verified by name instead.
allow |= {"/etc/skel", "/etc/sudoers.d", "/etc/systemd/system"}
missing = []
for pkg in root.glob("packages/*/files/etc"):
    for f in pkg.rglob("*"):
        if not f.is_file():
            continue
        if f.parent == pkg:
            # A file directly in /etc needs its own cp line in copy_product.
            if f.name not in inst:
                missing.append("/etc/" + f.name)
            continue
        d = "/etc/" + str(f.parent.relative_to(pkg))
        if not any(d == a or d.startswith(a + "/") for a in allow):
            missing.append(d)
for d in sorted(set(missing)):
    print(f"  FAIL {d} shipped but not copied by copy_product (live-only)")
sys.exit(1 if missing else 0)
PY
[[ "${fail}" -eq 0 ]] && say "copy_product allowlist covers every shipped /etc dir"

echo "==> no cicada unit hides in the live overlay"
# A unit that exists only under iso/overlay ships to the ISO and nowhere else,
# so copy_product cannot find it and the installed system silently never runs
# it. This is how cicada-firstboot came to be live-only. Units belong in a
# package; live-only behaviour is expressed with ConditionPathExists=/run/archiso.
ovl="${ROOT}/iso/overlay/airootfs/etc/systemd/system"
if [[ -d "${ovl}" ]]; then
  while IFS= read -r u; do
    die "$(basename "${u}") lives only in the overlay — move it to packages/cicada-defaults and gate with ConditionPathExists"
  done < <(find "${ovl}" -maxdepth 1 -name 'cicada-*' -type f)
fi
say "no overlay-only cicada units"

echo "==> every cicada unit is enabled somewhere, or is deliberately live-only"
for unit in "${ROOT}"/packages/cicada-defaults/files/etc/systemd/system/cicada-*; do
  u="$(basename "${unit}")"
  live=0; inst=0; cond=0
  grep -q "${u}" "${ASSEMBLE}" && live=1
  grep -q "${u%.service}" "${CHROOT}" && inst=1
  grep -q 'ConditionPathExists=/run/archiso' "${unit}" && cond=1
  case "${u}" in
    # Opt-in airplane at boot. Laptops are not phones; Wi-Fi stays available.
    cicada-radios-off.service) say "${u} (not enabled; CICADA_RADIOS_OFF_DEFAULT=0)"; continue ;;
    # Triggered by a udev RUN+= from cicada-amnesic, never enabled at boot.
    cicada-panic.service) say "${u} (udev-triggered, correctly not enabled)"; continue ;;
    # .service behind a .timer; the timer is what gets enabled.
    cicada-locked-reboot.service) say "${u} (driven by its timer)"; continue ;;
  esac
  if [[ "${cond}" -eq 1 ]]; then
    [[ "${live}" -eq 1 ]] && say "${u} (live-only by ConditionPathExists)" \
      || die "${u} is live-gated but not enabled on live"
  else
    [[ "${live}" -eq 1 && "${inst}" -eq 1 ]] && say "${u} (both sides)" \
      || die "${u} enabled on live=${live} installed=${inst} — one side will not run it"
  fi
done

echo "==> no overlay file is silently overwritten by a later rsync"
# assemble.sh rsyncs the overlay first, then every package, then skel -> /home.
# An overlay file that a later pass also provides is dead: edits to it do
# nothing, which is how a 'fix' can appear to have no effect.
shadowed=0
while IFS= read -r rel; do
  for p in cicada-defaults cicada-shell cicada-profiles cicada-run cicada-install; do
    if [[ -f "${ROOT}/packages/${p}/files/${rel}" ]]; then
      die "overlay ${rel} is overwritten by packages/${p} — the overlay copy is dead"
      shadowed=1
    fi
  done
  if [[ "${rel}" == home/cicada/* ]]; then
    if [[ -f "${ROOT}/packages/cicada-shell/files/etc/skel/${rel#home/cicada/}" ]]; then
      die "overlay ${rel} is overwritten by the skel->home copy — the overlay copy is dead"
      shadowed=1
    fi
  fi
done < <(cd "${ROOT}/iso/overlay/airootfs" && find . -type f | sed 's|^\./||')
[[ "${shadowed}" -eq 0 ]] && say "overlay files are all reachable"

echo "==> every shipped helper script is registered in file_permissions"
# mkarchiso only guarantees mode for files listed in profiledef file_permissions.
# An unlisted script can land non-executable, and if a pacman hook calls it the
# failure is "execv: Permission denied" on every transaction.
while IFS= read -r f; do
  rel="/usr/local/lib/cicada/$(basename "${f}")"
  grep -qF "\"${rel}\"" "${ASSEMBLE}" \
    || die "${rel} is shipped but not in file_permissions (may land non-executable)"
done < <(find "${ROOT}/packages" -path '*/usr/local/lib/cicada/*' -name '*.sh' -type f)
say "helper scripts all registered"

echo "==> live-only assets stay out of the installed product"
grep -q 'rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf' "${CHROOT}" \
  || die "installed system would inherit live autologin"
grep -q '^cicada::' "${ROOT}/iso/overlay/airootfs/etc/shadow" \
  || die "live user no longer passwordless (revisit cicada-lock guard)"
grep -q 'chpasswd' "${CHROOT}" || die "installed user never gets a real password"
say "autologin dropped / live passwordless / installed password set"

if [[ "${fail}" -ne 0 ]]; then
  echo "SEAM FAILED"
  exit 1
fi
echo "SEAM OK"
