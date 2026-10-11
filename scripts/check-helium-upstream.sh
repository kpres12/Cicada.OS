#!/usr/bin/env bash
# Class-A Helium cadence helper: compare channel/helium.lock to the latest
# imputnet/helium-linux release. Exit 0 if current; 1 if newer exists; 2 on error.
#
# Does not bump the lock — a human (or ISO rebuild) must re-pin after smoke test.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${ROOT}/channel/helium.lock"

[[ -f "${LOCK}" ]] || { echo "check-helium-upstream: missing ${LOCK}" >&2; exit 2; }

cur=""
while IFS='=' read -r k v; do
  [[ -z "${k}" || "${k}" == \#* ]] && continue
  [[ "${k}" == version ]] && cur="${v}"
done < "${LOCK}"
[[ -n "${cur}" ]] || { echo "check-helium-upstream: version= missing" >&2; exit 2; }

latest=""
if command -v gh >/dev/null 2>&1; then
  latest="$(gh api repos/imputnet/helium-linux/releases/latest --jq '.tag_name' 2>/dev/null | sed 's/^v//')"
fi
if [[ -z "${latest}" ]]; then
  api="https://api.github.com/repos/imputnet/helium-linux/releases/latest"
  latest="$(curl -fsSL -H 'Accept: application/vnd.github+json' "${api}" 2>/dev/null \
    | tr -d '\000-\037' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name","").lstrip("v"))' 2>/dev/null || true)"
fi
[[ -n "${latest}" ]] || { echo "check-helium-upstream: could not reach GitHub API" >&2; exit 2; }

echo "check-helium-upstream: pinned=${cur} latest=${latest}"
if [[ "${cur}" == "${latest}" ]]; then
  echo "check-helium-upstream: Helium pin is current"
  exit 0
fi

echo "check-helium-upstream: NEWER Helium available — Class A browser cadence applies"
echo "  1. Update channel/helium.lock (version + url + sha256)"
echo "  2. Bump packages/cicada-helium/PKGBUILD pkgver"
echo "  3. Rebuild ISO / publish via channel-build-meta + channel-publish-product"
echo "  Target: 72 hours from upstream release (docs/SECURITY_UPDATES.md)"
exit 1
