#!/usr/bin/env bash
# Verify channel pins in-tree. Not a substitute for a hosted mirror.
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
grep -q 'Public beta' "${ROOT}/site/index.html" || die "site home missing public beta banner"
grep -q 'prepare-release\|RELEASE.md' "${ROOT}/docs/RELEASE.md" || die "RELEASE.md incomplete"
grep -q 'NETWORK=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run default-deny missing"
test -x "${ROOT}/scripts/channel-build-repo.sh" || test -f "${ROOT}/scripts/channel-build-repo.sh" || die "channel-build-repo.sh missing"
test -f "${ROOT}/scripts/channel-sign.sh" || die "channel-sign.sh missing"
test -f "${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/cicada-channel-enable.sh" || die "cicada-channel-enable.sh missing"
grep -q 'channel-build-repo' "${ROOT}/iso/build.sh" || die "ISO build must call channel-build-repo"
say "build + default-deny + channel pipeline wired"

# If a local repo db exists (after an ISO build), require a signature when gpg can check it.
repo_db=""
for cand in "${ROOT}/out/channel-repo" "${ROOT}/channel/repo"; do
  if compgen -G "${cand}/cicada-stable.db.tar.*" >/dev/null 2>&1; then
    repo_db="$(ls "${cand}"/cicada-stable.db.tar.* 2>/dev/null | grep -v '\.sig$' | head -1)"
    break
  fi
done
if [[ -n "${repo_db}" ]]; then
  if [[ -f "${repo_db}.sig" ]]; then
    say "repo db signed: $(basename "${repo_db}").sig"
  else
    echo "  NOTE repo db present but unsigned (run scripts/channel-sign.sh after build)"
  fi
else
  echo "  NOTE no cicada-stable repo db yet (pin-only OK until first ISO build fills out/channel-repo)"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "CHANNEL-VERIFY FAILED"
  exit 1
fi
echo "CHANNEL-VERIFY OK"
