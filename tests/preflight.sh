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
say "assemble ok (see /tmp/cicada-assemble.log)"

echo "==> helium wrapper prefers official tarball"
grep -q '/opt/helium/chrome' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/chromium" || die "chromium wrapper"

if [[ "${fail}" -ne 0 ]]; then
  echo "PREFLIGHT FAILED"
  exit 1
fi
echo "PREFLIGHT OK"
