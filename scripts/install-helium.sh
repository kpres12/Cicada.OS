#!/usr/bin/env bash
# Install official Helium Linux into an airootfs. Not AUR.
# Pin: channel/helium.lock (version + url + sha256).
set -euo pipefail
DEST="${1:?airootfs}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${ROOT}/channel/helium.lock"

[[ -f "${LOCK}" ]] || { echo "error: missing ${LOCK}" >&2; exit 1; }

version=""; url=""; sha256=""
while IFS='=' read -r k v; do
  [[ -z "${k}" || "${k}" == \#* ]] && continue
  case "${k}" in
    version) version="${v}" ;;
    url) url="${v}" ;;
    sha256) sha256="${v}" ;;
  esac
done < "${LOCK}"
[[ -n "${url}" && -n "${sha256}" ]] || { echo "error: helium.lock incomplete" >&2; exit 1; }

CACHE="${HELIUM_CACHE:-${CICADA_WORK:-/tmp}/helium-cache}"
mkdir -p "${CACHE}"
tarball="${CACHE}/helium-${version}-x86_64_linux.tar.xz"

echo "==> Helium ${version}"
if [[ -f "${tarball}" ]]; then
  got="$(sha256sum "${tarball}" | awk '{print $1}')"
  if [[ "${got}" != "${sha256}" ]]; then
    echo "==> cached tarball hash mismatch, re-downloading"
    rm -f "${tarball}"
  fi
fi
if [[ ! -f "${tarball}" ]]; then
  curl -fL --retry 3 -o "${tarball}.part" "${url}"
  mv "${tarball}.part" "${tarball}"
fi
got="$(sha256sum "${tarball}" | awk '{print $1}')"
if [[ "${got}" != "${sha256}" ]]; then
  echo "error: Helium sha256 ${got} != ${sha256}" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xJf "${tarball}" -C "${work}"

bin=""
while IFS= read -r cand; do
  bin="${cand}"
  break
done < <(find "${work}" -type f \( -name chrome -o -name helium -o -name helium-browser \) -print | sort)

[[ -n "${bin}" && -f "${bin}" ]] || { echo "error: no Helium binary in tarball" >&2; exit 1; }
srcdir="$(dirname "${bin}")"

rm -rf "${DEST}/opt/helium"
mkdir -p "${DEST}/opt"
cp -a "${srcdir}" "${DEST}/opt/helium"
chmod 755 "${DEST}/opt/helium"
# chrome_sandbox is unused under cicada-run (nested user ns off) but keep the bit.
if [[ -f "${DEST}/opt/helium/chrome_sandbox" ]]; then
  chmod 4755 "${DEST}/opt/helium/chrome_sandbox" || true
fi

relbin="$(basename "${bin}")"
mkdir -p "${DEST}/usr/bin"
ln -sfn "/opt/helium/${relbin}" "${DEST}/usr/bin/helium"
ln -sfn "/opt/helium/${relbin}" "${DEST}/usr/bin/helium-browser"

# Helium reads Chromium-style enterprise policy from these trees.
for dest in \
  "${DEST}/etc/helium/policies" \
  "${DEST}/opt/helium/policies"
do
  mkdir -p "${dest}/managed" "${dest}/recommended"
  if [[ -d "${DEST}/etc/chromium/policies/managed" ]]; then
    cp -a "${DEST}/etc/chromium/policies/managed/." "${dest}/managed/"
  fi
  if [[ -d "${DEST}/etc/chromium/policies/recommended" ]]; then
    cp -a "${DEST}/etc/chromium/policies/recommended/." "${dest}/recommended/"
  fi
done

mkdir -p "${DEST}/etc/cicada"
printf '%s\n' "${version}" > "${DEST}/etc/cicada/helium.version"
echo "==> Helium ${version} -> /opt/helium (${relbin})"
