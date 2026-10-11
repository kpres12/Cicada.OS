#!/usr/bin/env bash
# Build Cicada product packages into the cicada-stable repo (Arch builder / Docker).
# These are the packages that make updates upgrade *Cicada*, not only Arch openssl.
#
# Signs each built package with the Cicada channel key (same key as the database).
# Arch packages keep their upstream .sig files; product packages get ours.
#
# Env:
#   CICADA_BUILD_HELIUM=1  — also build cicada-helium (needs network + ~100MB)
#   CICADA_BUILD_MALLOC=1  — also build cicada-malloc (needs gcc/git; default on
#                            when makepkg is present unless set to 0)
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

# Optional heavy / compiled product packages.
if [[ "${CICADA_BUILD_MALLOC:-1}" == "1" ]]; then
  PRODUCT_PKGS+=(cicada-malloc)
fi
if [[ "${CICADA_BUILD_HELIUM:-0}" == "1" ]]; then
  PRODUCT_PKGS+=(cicada-helium)
fi

stage_extras() {
  local name="$1" work="$2"
  case "${name}" in
    cicada-helium)
      cp -a "${ROOT}/channel/helium.lock" "${work}/helium.lock"
      cp -a "${ROOT}/scripts/install-helium.sh" "${work}/install-helium.sh"
      chmod +x "${work}/install-helium.sh"
      # Keep PKGBUILD pkgver in sync with the lock.
      local ver
      ver="$(awk -F= '/^version=/{print $2; exit}' "${work}/helium.lock")"
      if [[ -n "${ver}" ]]; then
        sed -i "s/^pkgver=.*/pkgver=${ver}/" "${work}/PKGBUILD" 2>/dev/null \
          || sed -i '' "s/^pkgver=.*/pkgver=${ver}/" "${work}/PKGBUILD"
      fi
      ;;
    cicada-malloc)
      cp -a "${ROOT}/channel/malloc.lock" "${work}/malloc.lock"
      cp -a "${ROOT}/scripts/build-hardened-malloc.sh" "${work}/build-hardened-malloc.sh"
      chmod +x "${work}/build-hardened-malloc.sh"
      local tag
      tag="$(awk -F= '/^tag=/{print $2; exit}' "${work}/malloc.lock")"
      if [[ -n "${tag}" ]]; then
        sed -i "s/^pkgver=.*/pkgver=${tag}/" "${work}/PKGBUILD" 2>/dev/null \
          || sed -i '' "s/^pkgver=.*/pkgver=${tag}/" "${work}/PKGBUILD"
      fi
      ;;
  esac
}

for name in "${PRODUCT_PKGS[@]}"; do
  src="${ROOT}/packages/${name}"
  [[ -f "${src}/PKGBUILD" ]] || continue
  work="$(mktemp -d)"
  cp -a "${src}/." "${work}/"
  stage_extras "${name}" "${work}"
  (
    cd "${work}"
    # File-tree packages: no compile step; deps are runtime on the target machine.
    # Helium/malloc need network + toolchain — allow deps for those.
    case "${name}" in
      cicada-malloc)
        # Needs a real toolchain on the builder; runtime deps are on the target.
        makepkg -f --nodeps --nocheck 2>/dev/null || makepkg -f --nodeps
        ;;
      cicada-helium)
        # Prebuilt upstream tarball — builder need not have GTK/nss installed.
        makepkg -f --nodeps --nocheck 2>/dev/null || makepkg -f --nodeps
        ;;
      *)
        makepkg -f --nodeps --nocheck 2>/dev/null || makepkg -f --nodeps
        ;;
    esac
  )
  shopt -s nullglob
  for pkg in "${work}"/*.pkg.tar.zst "${work}"/*.pkg.tar.xz; do
    base="$(basename "${pkg}")"
    cp -a "${pkg}" "${OUT}/${base}"
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
      repo-add -R cicada-stable.db.tar.zst "${built_names[@]}"
    else
      rm -f cicada-stable.db* cicada-stable.files* 2>/dev/null || true
      repo-add cicada-stable.db.tar.zst "${built_names[@]}"
    fi
    rm -f cicada-stable.db.tar.zst.old cicada-stable.files.tar.zst.old
  )
fi
echo "channel-build-meta: ${#built_names[@]} package(s) → ${OUT}"
