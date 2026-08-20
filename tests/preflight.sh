#!/usr/bin/env bash
# Run on the Mac (or anywhere with bash+python). No root. No bwrap.
# Exit 0 = scripts/assemble look coherent. Not a substitute for booting the Air.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  %s\n' "$*"; }
die() { printf 'FAIL %s\n' "$*"; fail=1; }

echo "==> bash -n"
while IFS= read -r f; do
  head="$(head -1 "$f" || true)"
  case "${head}" in
    *python*) continue ;;
    *bash*|*ash*|*sh*) ;;
    *) continue ;;
  esac
  bash -n "$f" || die "syntax $f"
done < <(find "${ROOT}/packages" "${ROOT}/iso" "${ROOT}/scripts" "${ROOT}/tests" -type f \( -name '*.sh' -o -path '*/usr/local/bin/*' -o -path '*/usr/lib/initcpio/hooks/*' \) ! -path '*/vendor/*')
say "syntax ok"

echo "==> chromium policy JSON"
python3 - <<PY
import json, pathlib, sys
root = pathlib.Path("${ROOT}")
for p in root.glob("packages/cicada-defaults/files/etc/chromium/policies/*/*.json"):
    json.loads(p.read_text())
    print(" ", p.name)
PY

echo "==> cicada-seal"
bash "${ROOT}/tests/seal.sh" || die "seal"

echo "==> sandbox syscall filter"
bash "${ROOT}/tests/seccomp.sh" >/dev/null || die "seccomp filter (run tests/seccomp.sh for detail)"
say "seccomp program decodes and returns the right verdicts"

echo "==> beacon + witness pairing"
bash "${ROOT}/tests/beacon.sh" >/dev/null || die "beacon (run tests/beacon.sh for detail)"
say "beacon signs, verifies, and alarms on a changed boot chain"

echo "==> AFU controls (USB gate, gate restore, watchdog, escape hatches)"
bash "${ROOT}/tests/afu.sh" >/dev/null || die "afu (run tests/afu.sh for detail)"
say "USB gate and watchdog behave under simulation; nomalloc rescue fires"

echo "==> messenger hosting"
bash "${ROOT}/tests/comms.sh" >/dev/null || die "comms (run tests/comms.sh for detail)"
say "cicada-comms refuses what it cannot protect"

echo "==> cicada-profile directory mode"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export CICADA_PROFILE_ROOT="${tmp}/profiles"
export HOME="${tmp}/home"
mkdir -p "${HOME}"
prof="${ROOT}/packages/cicada-profiles/files/usr/local/bin/cicada-profile"
bash "${prof}" create burner >/dev/null
bash "${prof}" switch burner >/dev/null
grep -q CICADA_PROFILE=burner "${HOME}/.local/share/cicada/current-profile" || die "switch did not stick"
# dispose wants cicada-auth; skip by PATH without auth... it still calls cicada-auth if on PATH
PATH="/usr/bin:/bin" CICADA_PROFILE_ROOT="${tmp}/profiles" HOME="${HOME}" bash "${prof}" dispose burner >/dev/null || die "dispose"
say "profile create/switch/dispose ok"

echo "==> required strings"
grep -q 'cicada-crypt' "${ROOT}/packages/cicada-install/files/usr/local/lib/cicada/install-chroot.sh" || die "install-chroot missing cicada-crypt"
grep -q 'copytoram' "${ROOT}/iso/assemble-profile.sh" || die "assemble missing copytoram"
grep -q 'ibt=on shstk=on' "${ROOT}/iso/assemble-profile.sh" || die "assemble missing CET cmdline"
grep -q 'cicada-amnesic.service' "${ROOT}/iso/assemble-profile.sh" || die "assemble missing amnesic unit"
grep -q 'cicada-yank-watch' "${ROOT}/iso/assemble-profile.sh" || die "assemble missing yank-watch"
test -f "${ROOT}/docs/USER.md" || die "docs/USER.md missing"
test -x "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-duress-enroll" || die "duress enroll not executable"
test -f "${ROOT}/packages/cicada-defaults/files/usr/lib/initcpio/hooks/cicada-crypt" || die "cicada-crypt hook missing"
say "strings ok"

echo "==> assemble-profile"
export CICADA_PROFILE_DIR="${tmp}/profile"
bash "${ROOT}/iso/assemble-profile.sh" >/tmp/cicada-assemble.log 2>&1 || {
  tail -20 /tmp/cicada-assemble.log
  die "assemble-profile"
}
test -f "${tmp}/profile/airootfs/usr/share/cicada/FIRST-BOOT.txt" || die "FIRST-BOOT.txt not in profile"
test -x "${tmp}/profile/airootfs/usr/local/bin/cicada-install" || die "cicada-install not 755 in profile"
test -x "${tmp}/profile/airootfs/usr/local/bin/cicada-panic" || die "cicada-panic missing in profile"
grep -q copytoram "${tmp}/profile/efiboot/loader/entries/"*.conf 2>/dev/null \
  || grep -Rql copytoram "${tmp}/profile/efiboot" || die "copytoram not in boot entries"
# pacman.conf is sectioned and NoExtract/DisableSandbox are valid ONLY under
# [options]. Appending them to the end of the file lands them inside whatever
# repository section is last; pacman logs "directive not recognized" and ignores
# them. That is not hypothetical — it shipped: the build printed that it had set
# NoExtract, and all 6349 files under usr/share/doc were on the image anyway.
# Assert the section, not the presence of the string.
python3 - "${tmp}/profile/pacman.conf" <<'PYCONF' || die "pacman.conf directives are not in [options] (they would be silently ignored)"
import sys, pathlib
sec = None
bad, seen = [], []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    s = line.strip()
    if s.startswith("[") and s.endswith("]"):
        sec = s
    elif s and not s.startswith("#"):
        key = s.split("=")[0].strip()
        if key in ("NoExtract", "DisableSandbox"):
            seen.append(s)
            if sec != "[options]":
                bad.append(f"{s}  is in {sec}, must be [options]")
if bad:
    print("  " + "\n  ".join(bad))
    sys.exit(1)
if not any(x.startswith("NoExtract") for x in seen):
    print("  no NoExtract set at all — usr/share/doc will ship")
    sys.exit(1)

# Licence compliance. 9 of the first 400 packages on this image (acl, attr,
# bison, dosfstools, firejail, libdvdnav, libdvdread, libexif, appstream) ship
# their COPYING/LICENSE ONLY under usr/share/doc, never usr/share/licenses.
# Excluding that directory wholesale strips the licence text from GPL and LGPL
# binaries we redistribute.
#
# And the ORDER decides whether the exceptions do anything at all: alpm's
# _alpm_fnmatch_patterns() walks the list from the END and returns on the first
# match, so the LAST matching line wins. Exceptions must come AFTER the broad
# rule. Asserting only that the "!" lines exist would pass a config where they
# are ignored.
pats = [x.split("=", 1)[1].strip() for x in seen if x.startswith("NoExtract")]
if "usr/share/doc/*" in pats:
    broad = pats.index("usr/share/doc/*")
    keep = [i for i, p in enumerate(pats)
            if p.startswith("!") and any(w in p.upper() for w in ("COPYING", "LICENSE", "LICENCE", "COPYRIGHT"))]
    if not keep:
        print("  usr/share/doc is excluded with no licence exceptions — strips GPL/LGPL licence text")
        sys.exit(1)
    if min(keep) < broad:
        print("  licence exceptions appear BEFORE the broad rule; the last match wins, so they do nothing")
        sys.exit(1)
sys.exit(0)
PYCONF
say "pacman.conf: NoExtract/DisableSandbox land in [options], where pacman reads them"

say "assemble ok (see /tmp/cicada-assemble.log)"

echo "==> helium wrapper prefers official tarball"
grep -q '/opt/helium/chrome' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/chromium" || die "chromium wrapper"

if [[ "${fail}" -ne 0 ]]; then
  echo "PREFLIGHT FAILED"
  exit 1
fi
echo "PREFLIGHT OK"
