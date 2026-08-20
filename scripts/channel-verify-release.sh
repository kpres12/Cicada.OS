#!/usr/bin/env bash
# Every package the SIGNED database names must be downloadable from one of the
# release roots, before either release stops being a draft.
#
# This exists because a half-uploaded mirror is worse than no mirror. A repo that
# 404s outright makes cicada-update fail cleanly and say so; a repo whose
# database lists packages the mirror does not serve fails partway through an
# upgrade on somebody's machine, which is the state that leaves a system with
# half its packages replaced.
#
# It is not hypothetical: the first upload of this channel hit GitHub's
# undocumented-in-the-UI 1000-asset ceiling and returned HTTP 422 for every
# asset after the thousandth, leaving a release that looked populated and was
# missing a third of its packages.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${1:-${ROOT}/out/channel-repo}"
TAG="${2:-channel-latest}"
TAG2="${TAG}-2"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT

command -v gh >/dev/null || { echo "channel-verify-release: gh required" >&2; exit 1; }
db="${REPO}/cicada-stable.db.tar.zst"
[[ -f "${db}" ]] || { echo "channel-verify-release: no database at ${db}" >&2; exit 1; }

# What the database promises exists.
bsdtar -xOf "${db}" 2>/dev/null \
  | grep -A1 '^%FILENAME%$' | grep -vE '^(%FILENAME%|--)$' | sed '/^$/d' | sort -u > "${tmp}/want"

# What the releases actually serve.
: > "${tmp}/have"
for t in "${TAG}" "${TAG2}"; do
  gh release view "${t}" --json assets -q '.assets[].name' 2>/dev/null >> "${tmp}/have" || true
done
sort -u "${tmp}/have" -o "${tmp}/have"

want=$(wc -l < "${tmp}/want" | tr -d ' ')
have=$(wc -l < "${tmp}/have" | tr -d ' ')
echo "packages named by the signed database : ${want}"
echo "assets across ${TAG} + ${TAG2}          : ${have}"

rc=0
comm -23 "${tmp}/want" "${tmp}/have" > "${tmp}/missing"
n_missing=$(wc -l < "${tmp}/missing" | tr -d ' ')
echo "named by the database, NOT uploaded   : ${n_missing}"
if [[ "${n_missing}" -gt 0 ]]; then
  echo "--- first 10 ---"; head -10 "${tmp}/missing"; rc=1
fi

# SigLevel=Required checks each package signature, so a missing .sig fails the
# upgrade just as surely as a missing package.
sed 's/$/.sig/' "${tmp}/want" | sort -u > "${tmp}/want_sig"
comm -23 "${tmp}/want_sig" "${tmp}/have" > "${tmp}/missing_sig"
n_missing_sig=$(wc -l < "${tmp}/missing_sig" | tr -d ' ')
echo "packages missing their .sig           : ${n_missing_sig}"
[[ "${n_missing_sig}" -gt 0 ]] && { head -5 "${tmp}/missing_sig"; rc=1; }

for d in cicada-stable.db cicada-stable.db.sig cicada-stable.files cicada-stable.files.sig; do
  if grep -qx "${d}" "${tmp}/have"; then echo "  present: ${d}"; else echo "  MISSING: ${d}"; rc=1; fi
done

if [[ "${rc}" -ne 0 ]]; then
  echo
  echo "NOT SAFE TO PUBLISH — leave both releases as drafts and re-run channel-publish.sh."
  exit 1
fi
echo
echo "complete — safe to publish:"
echo "  gh release edit ${TAG} --draft=false"
echo "  gh release edit ${TAG2} --draft=false"
