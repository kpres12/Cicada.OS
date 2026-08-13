#!/usr/bin/env bash
# Verify channel pins in-tree. Not a substitute for a signed pacman repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

echo "==> channel pins"
test -f "${ROOT}/channel/CURRENT" || die "CURRENT missing"
cur="$(tr -d '[:space:]' < "${ROOT}/channel/CURRENT")"
test -f "${ROOT}/channel/${cur}.pkglist.txt" || die "pkglist for ${cur} missing"
say "CURRENT=${cur}"

lock="${ROOT}/channel/helium.lock"
test -f "${lock}" || die "helium.lock missing"
grep -q '^version=' "${lock}" || die "helium.lock version"
grep -q '^url=https://github.com/imputnet/helium-linux/' "${lock}" || die "helium.lock url"
grep -Eq '^sha256=[0-9a-f]{64}$' "${lock}" || die "helium.lock sha256"
say "helium.lock pinned"

grep -q 'install-helium.sh' "${ROOT}/iso/build.sh" || die "ISO build does not install Helium"
grep -q 'NETWORK=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run default-deny missing"
say "build + default-deny wired"

if [[ "${fail}" -ne 0 ]]; then
  echo "CHANNEL-VERIFY FAILED"
  exit 1
fi
echo "CHANNEL-VERIFY OK"
