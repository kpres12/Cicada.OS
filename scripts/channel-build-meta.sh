#!/usr/bin/env bash
# Build Cicada product packages into the cicada-stable repo (Arch builder / Docker).
# These are the packages that make updates upgrade *Cicada*, not only Arch openssl.
#
# Signs each built package with the Cicada channel key (same key as the database).
# Arch packages keep their upstream .sig files; product packages get ours.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/out/channel-repo}"
KEYS="${ROOT}/channel/keys"
export GNUPGHOME="${KEYS}/gnupg"

command -v makepkg >/dev/null 2>&1 || {
  echo "channel-build-meta: makepkg missing — skip" >&2
  exit 0
}

mkdir -p "${OUT}"
built_names=()
# Order: leaf packages before the desktop meta that depends on them.
PRODUCT_PKGS=(
  cicada-run
  cicada-defaults
  cicada-profiles
  cicada-install
  cicada-shell
  cicada-desktop
)

for name in "${PRODUCT_PKGS[@]}"; do
  src="${ROOT}/packages/${name}"
  [[ -f "${src}/PKGBUILD" ]] || continue
  work="$(mktemp -d)"
  cp -a "${src}/." "${work}/"
  (
    cd "${work}"
    # File-tree packages: no compile step; deps are runtime on the target machine.
    makepkg -f --nodeps --nocheck 2>/dev/null || makepkg -f --nodeps
  )
  shopt -s nullglob
  for pkg in "${work}"/*.pkg.tar.zst "${work}"/*.pkg.tar.xz; do
    base="$(basename "${pkg}")"
    cp -a "${pkg}" "${OUT}/${base}"
    # Product packages are not Arch-developer-signed — sign with Cicada.
    if command -v gpg >/dev/null 2>&1 \
       && [[ -d "${GNUPGHOME}" ]] \
       && gpg --list-secret-keys "stable@cicada.os" >/dev/null 2>&1; then
      rm -f "${OUT}/${base}.sig"
      gpg --batch --yes --detach-sign --default-key "stable@cicada.os" "${OUT}/${base}"
      echo "channel-build-meta: ${base} (+ Cicada .sig)"
    else
      echo "channel-build-meta: ${base} (UNSIGNED — channel-sign key missing)" >&2
    fi
    built_names+=("${base}")
  done
  rm -rf "${work}"
done

if [[ ${#built_names[@]} -eq 0 ]]; then
  echo "channel-build-meta: nothing built"
  exit 0
fi

if command -v repo-add >/dev/null 2>&1; then
  (
    cd "${OUT}"
    if compgen -G 'cicada-stable.db.tar.*' >/dev/null; then
      # Fold only the packages we just built into the existing Arch snapshot DB.
      repo-add cicada-stable.db.tar.zst "${built_names[@]}"
    else
      rm -f cicada-stable.db* cicada-stable.files* 2>/dev/null || true
      repo-add cicada-stable.db.tar.zst "${built_names[@]}"
    fi
  )
fi
echo "channel-build-meta: ${#built_names[@]} package(s) → ${OUT}"
