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
slug="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo kpres12/Cicada.OS)"
root="https://github.com/${slug}/releases/download/${TAG}"

cat > "${notes}" <<EOF
Cicada.OS channel mirror (${pin}).

This is the tested Arch snapshot the matching ISO was built from — kernel,
openssl, browser runtime and the rest. The database is signed with the Cicada
stable key that ships in \`/etc/pacman.d/cicada-stable-key.gpg\`; each package
keeps its original Arch developer signature. \`cicada-update\` syncs only this
repository. Raw Arch rolling is not the product update path.

Cicada.OS images from this release onward point here automatically — there is
nothing to configure. Updates are pulled only when the user runs
\`cicada-update\` (Settings → Security → Check updates); nothing polls.

To point an older install at it by hand:

  echo '${root}' | sudo tee /etc/cicada/channel-mirror.url
  sudo /usr/local/lib/cicada/cicada-channel-enable.sh
  sudo cicada-update
EOF

# --- GitHub caps a release at 1000 assets --------------------------------
#
# A full snapshot is ~907 packages, and SigLevel=Required means each one ships
# with its .sig, so the repo is ~1814 files plus the database — comfortably over
# the cap. The upload does not fail cleanly either: it uploads 1000 assets and
# then returns HTTP 422 "file_count limited to 1000 assets per release" for
# every one after that, leaving a release that looks populated and is missing a
# third of its packages.
#
# The fix keeps every security property rather than trading one away. pacman
# accepts multiple `Server =` lines for one repository and falls through to the
# next on a miss (verified, not assumed), so the snapshot is split across two
# releases and /etc/cicada/channel-mirror.url names both. Per-package Arch
# signatures stay, and SigLevel stays Required.
#
# The alternative — dropping the .sig files and trusting only the signed
# database — would halve the asset count, and was rejected: the database records
# a sha256 for every package, but that is Cicada vouching for the bytes instead
# of the Arch developer who built them, and that is a real reduction in what a
# user can check.
shopt -s nullglob
db_assets=("${REPO}"/cicada-stable.db* "${REPO}"/cicada-stable.files*)
pkgs=("${REPO}"/*.pkg.tar.zst)
[[ ${#pkgs[@]} -gt 0 ]] || { echo "channel-publish: repo empty" >&2; exit 1; }

MAX_ASSETS=1000
# Room for the database set on the first release, and pairs are kept together so
# a package and its signature never land on different servers.
room1=$(( (MAX_ASSETS - ${#db_assets[@]}) / 2 ))
(( room1 > 0 )) || { echo "channel-publish: database alone exceeds the asset cap" >&2; exit 1; }

first=("${db_assets[@]}")
second=()
i=0
for pkg in "${pkgs[@]}"; do
  sig="${pkg}.sig"
  if (( i < room1 )); then
    first+=("${pkg}"); [[ -f "${sig}" ]] && first+=("${sig}")
  else
    second+=("${pkg}"); [[ -f "${sig}" ]] && second+=("${sig}")
  fi
  i=$((i + 1))
done

TAG2="${TAG}-2"
echo "channel-publish: ${#pkgs[@]} packages"
echo "  ${TAG}   <- ${#first[@]} assets (database + first ${room1} packages)"
echo "  ${TAG2} <- ${#second[@]} assets"
(( ${#first[@]} <= MAX_ASSETS )) || { echo "channel-publish: split miscomputed" >&2; exit 1; }
(( ${#second[@]} <= MAX_ASSETS )) || {
  echo "channel-publish: snapshot needs a third release — extend the split" >&2; exit 1; }

# Upload in batches: one gh invocation per 1800 arguments would exceed ARG_MAX,
# and a batch that fails is retried rather than silently skipped.
upload_batched() {
  local tag="$1"; shift
  local -a batch=()
  local n=0 total=$#
  for a in "$@"; do
    batch+=("${a}")
    if [[ ${#batch[@]} -ge 25 ]]; then
      gh release upload "${tag}" "${batch[@]}" --clobber \
        || gh release upload "${tag}" "${batch[@]}" --clobber \
        || { echo "channel-publish: batch failed on ${tag}" >&2; return 1; }
      n=$((n + ${#batch[@]})); batch=(); echo "    ${tag}: ${n}/${total}"
    fi
  done
  if [[ ${#batch[@]} -gt 0 ]]; then
    gh release upload "${tag}" "${batch[@]}" --clobber || return 1
    n=$((n + ${#batch[@]})); echo "    ${tag}: ${n}/${total}"
  fi
}

for pair in "${TAG}" "${TAG2}"; do
  if ! gh release view "${pair}" >/dev/null 2>&1; then
    # Created as a draft on purpose: a half-uploaded mirror that is already
    # public breaks `pacman -Sy` mid-upgrade on real machines. Publish only
    # after scripts/channel-verify-release.sh says the set is complete.
    gh release create "${pair}" --draft \
      --title "Cicada channel ${pin}$([[ "${pair}" == "${TAG2}" ]] && echo ' (part 2)')" \
      --notes-file "${notes}"
  fi
done

upload_batched "${TAG}" "${first[@]}" || exit 1
upload_batched "${TAG2}" "${second[@]}" || exit 1

rm -f "${notes}"

cat <<EOF

channel-publish: uploaded, still DRAFT (invisible to users).

  ${TAG}   ${#first[@]} assets
  ${TAG2} ${#second[@]} assets

Next, in this order — publishing a mirror that is missing packages breaks
\`pacman -Sy\` on real machines, and that is worse than a mirror that 404s:

  scripts/channel-verify-release.sh          # every package the signed db names
  gh release edit ${TAG} --draft=false
  gh release edit ${TAG2} --draft=false

/etc/cicada/channel-mirror.url must name BOTH roots, in this order:
  https://github.com/${slug}/releases/download/${TAG}
  https://github.com/${slug}/releases/download/${TAG2}
EOF
