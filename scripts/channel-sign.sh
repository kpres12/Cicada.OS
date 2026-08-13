#!/usr/bin/env bash
# Sign cicada-stable repo database. Public key ships on the ISO; private key is local-only.
# Usage: channel-sign.sh [repo-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${1:-${ROOT}/out/channel-repo}"
KEYS="${ROOT}/channel/keys"
PUB_EXPORT="${KEYS}/cicada-stable.pub"
ISO_PUB="${ROOT}/packages/cicada-defaults/files/etc/pacman.d/cicada-stable-key.gpg"

mkdir -p "${KEYS}"

if ! command -v gpg >/dev/null 2>&1; then
  echo "channel-sign: gpg missing — skip" >&2
  exit 0
fi

# Dev key email — product identity, rotate for releases.
KEY_UID="Cicada.OS stable <stable@cicada.os>"
export GNUPGHOME="${KEYS}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

if ! gpg --list-secret-keys "stable@cicada.os" >/dev/null 2>&1; then
  echo "channel-sign: generating dev signing key (private stays under channel/keys/gnupg — gitignored)"
  cat > "${KEYS}/batch-keygen" <<EOF
%no-protection
Key-Type: EdDSA
Key-Curve: Ed25519
Key-Usage: sign
Name-Real: Cicada.OS stable
Name-Email: stable@cicada.os
Expire-Date: 0
%commit
EOF
  gpg --batch --generate-key "${KEYS}/batch-keygen"
  rm -f "${KEYS}/batch-keygen"
fi

gpg --armor --export "stable@cicada.os" > "${PUB_EXPORT}"
mkdir -p "$(dirname "${ISO_PUB}")"
# Binary keyring form for pacman-key --add (also keep armored pub)
gpg --export "stable@cicada.os" > "${ISO_PUB}"
cp -a "${PUB_EXPORT}" "${ROOT}/packages/cicada-defaults/files/etc/pacman.d/cicada-stable-key.asc" 2>/dev/null || true

if [[ ! -d "${REPO}" ]]; then
  echo "channel-sign: repo dir ${REPO} missing — pubkey exported only"
  exit 0
fi

db="$(ls "${REPO}"/cicada-stable.db.tar.* 2>/dev/null | head -1 || true)"
if [[ -z "${db}" ]]; then
  echo "channel-sign: no cicada-stable.db in ${REPO}"
  exit 0
fi

rm -f "${db}.sig"
gpg --batch --yes --detach-sign --default-key "stable@cicada.os" "${db}"
# Also sign .files db if present
files="$(ls "${REPO}"/cicada-stable.files.tar.* 2>/dev/null | grep -v '\.sig$' | head -1 || true)"
if [[ -n "${files}" ]]; then
  rm -f "${files}.sig"
  gpg --batch --yes --detach-sign --default-key "stable@cicada.os" "${files}"
fi

echo "channel-sign: signed ${db}"
echo "channel-sign: pubkey → ${PUB_EXPORT} and ISO ${ISO_PUB}"
