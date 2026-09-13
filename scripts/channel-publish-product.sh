#!/usr/bin/env bash
# Fold Cicada product packages into the *published* channel DB and upload them.
# Does NOT republish the full Arch snapshot — only cicada-* + updated signed DB.
#
# Usage: scripts/channel-publish-product.sh [product-pkgs-dir] [tag]
# Requires: docker (repo-add), gh auth, channel signing key.
#
# GitHub caps a release at 1000 assets. Database assets stay on $TAG;
# product packages upload to ${TAG}-2 (pacman falls through Server= lines).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD="${1:-${ROOT}/out/product-pkgs}"
TAG="${2:-channel-latest}"
OVERFLOW="${TAG}-2"
WORK="${ROOT}/out/channel-product-merge"
KEYS="${ROOT}/channel/keys"
export GNUPGHOME="${KEYS}/gnupg"

[[ -d "${PROD}" ]] || { echo "channel-publish-product: missing ${PROD}" >&2; exit 1; }
command -v gh >/dev/null || { echo "channel-publish-product: gh CLI required" >&2; exit 1; }
command -v docker >/dev/null || { echo "channel-publish-product: docker required for repo-add" >&2; exit 1; }
gpg --list-secret-keys "stable@cicada.os" >/dev/null 2>&1 \
  || { echo "channel-publish-product: Cicada signing key missing" >&2; exit 1; }

shopt -s nullglob
pkgs=("${PROD}"/cicada-*.pkg.tar.zst)
[[ ${#pkgs[@]} -gt 0 ]] || { echo "channel-publish-product: no cicada-*.pkg.tar.zst in ${PROD}" >&2; exit 1; }

for pkg in "${pkgs[@]}"; do
  if [[ ! -f "${pkg}.sig" ]]; then
    gpg --batch --yes --detach-sign --default-key "stable@cicada.os" "${pkg}"
  fi
done

rm -rf "${WORK}"
mkdir -p "${WORK}"
for pkg in "${pkgs[@]}"; do
  cp -a "${pkg}" "${WORK}/"
  [[ -f "${pkg}.sig" ]] && cp -a "${pkg}.sig" "${WORK}/"
done

slug="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo kpres12/Cicada.OS)"
base="https://github.com/${slug}/releases/download/${TAG}"

echo "channel-publish-product: fetching published database from ${TAG}"
curl -fsSL -o "${WORK}/cicada-stable.db.tar.zst" "${base}/cicada-stable.db.tar.zst" \
  || { echo "channel-publish-product: could not download cicada-stable.db.tar.zst from ${TAG}" >&2; exit 1; }
curl -fsSL -o "${WORK}/cicada-stable.files.tar.zst" "${base}/cicada-stable.files.tar.zst" 2>/dev/null || true

echo "channel-publish-product: repo-add product packages into published DB"
docker run --rm --platform linux/amd64 --entrypoint bash \
  -v "${WORK}:/repo" -w /repo cicada-iso-builder:latest -lc '
set -e
pacman -Sy --noconfirm --needed pacman-contrib >/dev/null
shopt -s nullglob
pkgs=(cicada-*.pkg.tar.zst)
repo-add -R cicada-stable.db.tar.zst "${pkgs[@]}"
rm -f cicada-stable.db.tar.zst.old cicada-stable.files.tar.zst.old
for short in db files; do
  if [[ -L "cicada-stable.${short}" ]]; then
    target="$(readlink "cicada-stable.${short}")"
    rm -f "cicada-stable.${short}"
    cp -a "${target}" "cicada-stable.${short}"
  fi
done
'

bash "${ROOT}/scripts/channel-sign.sh" "${WORK}"
# repo-add leaves *.old; never publish those (they burn asset slots).
rm -f "${WORK}"/cicada-stable.*.old

DB_NAMES=(
  cicada-stable.db
  cicada-stable.db.sig
  cicada-stable.db.tar.zst
  cicada-stable.db.tar.zst.sig
  cicada-stable.files
  cicada-stable.files.sig
  cicada-stable.files.tar.zst
  cicada-stable.files.tar.zst.sig
)

echo "channel-publish-product: replacing DB assets on ${TAG}"
for name in "${DB_NAMES[@]}" cicada-stable.db.tar.zst.old cicada-stable.files.tar.zst.old; do
  if gh release view "${TAG}" --json assets --jq '.assets[].name' | grep -Fxq "${name}"; then
    gh release delete-asset "${TAG}" "${name}" -y
  fi
done

db_assets=()
for name in "${DB_NAMES[@]}"; do
  [[ -f "${WORK}/${name}" ]] && db_assets+=("${WORK}/${name}")
done
gh release upload "${TAG}" "${db_assets[@]}"

if ! gh release view "${OVERFLOW}" >/dev/null 2>&1; then
  pin="$(cat "${ROOT}/channel/CURRENT" 2>/dev/null || echo unknown)"
  gh release create "${OVERFLOW}" --title "Cicada channel overflow (${pin})" \
    --notes "Overflow mirror for ${TAG}. Packages that did not fit under the 1000-asset cap."
fi

pkg_assets=()
for f in "${WORK}"/cicada-*.pkg.tar.zst "${WORK}"/cicada-*.pkg.tar.zst.sig; do
  [[ -f "${f}" ]] && pkg_assets+=("${f}")
done
echo "channel-publish-product: uploading ${#pkgs[@]} product package(s) to ${OVERFLOW}"
gh release upload "${OVERFLOW}" "${pkg_assets[@]}" --clobber

pin="$(cat "${ROOT}/channel/CURRENT" 2>/dev/null || echo unknown)"
echo "channel-publish-product: done — DB on ${TAG}; packages on ${OVERFLOW} (pin ${pin})"
echo "channel-publish-product: machines pick them up via cicada-update"
