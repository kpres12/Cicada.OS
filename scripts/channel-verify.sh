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

doom="${ROOT}/channel/doom.lock"
test -f "${doom}" || die "doom.lock missing"
grep -q '^engine_version=' "${doom}" || die "doom.lock engine_version"
grep -q '^engine_url=https://github.com/chocolate-doom/' "${doom}" || die "doom.lock engine_url"
grep -Eq '^engine_sha256=[0-9a-f]{64}$' "${doom}" || die "doom.lock engine_sha256"
grep -q '^wad_url=https://github.com/freedoom/' "${doom}" || die "doom.lock wad_url"
grep -Eq '^wad_sha256=[0-9a-f]{64}$' "${doom}" || die "doom.lock wad_sha256"
say "doom.lock pinned (Chocolate Doom + Freedoom)"

grep -q 'install-helium.sh' "${ROOT}/iso/build.sh" || die "ISO build does not install Helium"
grep -q 'install-doom.sh' "${ROOT}/iso/build.sh" || die "ISO build does not install Doom"
# The site must not claim a maturity the README does not. Two earlier versions of
# this check were wrong in instructive ways. Asserting the literal string
# "Public beta" pinned the marketing copy while the README's ## Status section
# said pre-alpha, so the two drifted and the check still passed. Grepping the
# whole page for the README's word then matched the status *panel* further down
# rather than the banner, so a banner that said "Public beta" also passed.
#
# So: extract the banner's own text and compare that. And read the README word
# from ## Status, not from the first bolded line — that one is the download
# blurb at the top, which is how the two came to disagree in the first place.
banner="$(sed -n 's/.*class="beta-pill"[^>]*>\([^<]*\).*/\1/p' "${ROOT}/site/index.html" | head -1)"
readme_status="$(sed -n '/^## Status/,/^## /p' "${ROOT}/README.md" \
  | grep -oiE '\*\*(Pre-alpha|Alpha|Beta|Public beta|Stable)' | head -1 | tr -d '*')"
if [[ -z "${banner}" ]]; then
  die "site home has no status banner (.beta-pill) to check"
elif [[ -z "${readme_status}" ]]; then
  die "README ## Status has no bolded maturity word to compare the site against"
elif ! grep -qiF "${readme_status}" <<<"${banner}"; then
  die "site banner says '${banner}' but README ## Status says '${readme_status}'"
else
  say "site banner agrees with README ## Status (${readme_status})"
fi
grep -q 'prepare-release\|RELEASE.md' "${ROOT}/docs/RELEASE.md" || die "RELEASE.md incomplete"
grep -q 'NETWORK=deny' "${ROOT}/packages/cicada-run/files/usr/local/bin/cicada-run" || die "cicada-run default-deny missing"
test -f "${ROOT}/scripts/channel-build-repo.sh" || die "channel-build-repo.sh missing"
test -f "${ROOT}/scripts/channel-build-meta.sh" || die "channel-build-meta.sh missing"
test -f "${ROOT}/scripts/channel-sign.sh" || die "channel-sign.sh missing"
test -f "${ROOT}/scripts/channel-publish.sh" || die "channel-publish.sh missing"
test -f "${ROOT}/packages/cicada-desktop/PKGBUILD" || die "cicada-desktop meta PKGBUILD missing"
test -f "${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/cicada-channel-enable.sh" || die "cicada-channel-enable.sh missing"
grep -q 'channel-mirror.url' "${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/cicada-channel-enable.sh" \
  || die "channel-enable must honor hosted mirror URL"
grep -q 'pacman -Slq cicada-stable\|Slq cicada-stable' "${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-update" \
  || die "cicada-update must upgrade channel packages only"
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
