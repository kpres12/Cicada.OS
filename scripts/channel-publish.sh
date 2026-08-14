#!/usr/bin/env bash
# Publish out/channel-repo as a GitHub Release asset set for cicada-stable.
# Usage: channel-publish.sh [repo-dir] [tag]
# Requires: gh auth, channel-sign.sh already run (or runs it).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${1:-${ROOT}/out/channel-repo}"
TAG="${2:-channel-latest}"

[[ -d "${REPO}" ]] || { echo "channel-publish: missing ${REPO} (build an ISO first)" >&2; exit 1; }
command -v gh >/dev/null || { echo "channel-publish: gh CLI required" >&2; exit 1; }

bash "${ROOT}/scripts/channel-sign.sh" "${REPO}"

pin="$(cat "${ROOT}/channel/CURRENT" 2>/dev/null || echo unknown)"
notes="$(mktemp)"
cat > "${notes}" <<EOF
Cicada.OS channel mirror (${pin}).

On a machine:
  echo 'https://github.com/OWNER/REPO/releases/download/${TAG}' | sudo tee /etc/cicada/channel-mirror.url
  sudo cicada-channel-enable.sh
  sudo cicada-update

Replace OWNER/REPO with this GitHub repository.
EOF

# Upload every pkg + db + sig (may be large).
shopt -s nullglob
assets=("${REPO}"/*.pkg.tar.* "${REPO}"/cicada-stable.db* "${REPO}"/cicada-stable.files*)
[[ ${#assets[@]} -gt 0 ]] || { echo "channel-publish: repo empty" >&2; exit 1; }

if gh release view "${TAG}" >/dev/null 2>&1; then
  gh release upload "${TAG}" "${assets[@]}" --clobber
else
  gh release create "${TAG}" "${assets[@]}" \
    --title "Cicada channel ${pin}" \
    --notes-file "${notes}"
fi
rm -f "${notes}"

url="$(gh release view "${TAG}" --json url -q .url 2>/dev/null || true)"
echo "channel-publish: ${TAG} (${#assets[@]} assets)"
echo "channel-publish: set Server to the release download root, e.g."
echo "  https://github.com/OWNER/REPO/releases/download/${TAG}"
[[ -n "${url}" ]] && echo "channel-publish: ${url}"
