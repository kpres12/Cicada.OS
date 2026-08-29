#!/usr/bin/env bash
# Freeze the package set from a built ISO's pkglist into channel/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="${1:-$(date -u +%Y.%m.%d)}"
SRC="${2:-}"

# Default to the built repo, not the newest ISO. This file pins what the
# *channel* serves, and the channel is out/channel-repo — the builder's pacman
# cache, which is a superset of the ISO's own package set (the ISO installs 654
# of the snapshot's 860). Defaulting to the ISO meant the default path always
# fell through to the error below, so in practice the pin was only ever written
# by hand, which is how CURRENT came to name a 2026.08.12 set while the mirror
# served the 2026.08.20 one: 207 packages it did not list and 43 at different
# versions, bind and ca-certificates-mozilla among them.
if [[ -z "${SRC}" ]]; then
  if compgen -G "${ROOT}/out/channel-repo/cicada-stable.db.tar.*" >/dev/null 2>&1; then
    SRC="${ROOT}/out/channel-repo"
  else
    SRC="$(ls -1t "${ROOT}"/out/cicada-*.iso 2>/dev/null | head -1 || true)"
  fi
fi
[[ -n "${SRC}" ]] || { echo "usage: channel-snapshot.sh [YYYY.MM.DD] [repo-dir|db|pkglist]"; exit 1; }

# A repo dir is named by its database, so accept either.
if [[ -d "${SRC}" ]]; then
  SRC="$(ls "${SRC}"/cicada-stable.db.tar.* 2>/dev/null | grep -v '\.sig$' | head -1 || true)"
  [[ -n "${SRC}" ]] || { echo "channel-snapshot: no cicada-stable.db in ${2:-${ROOT}/out/channel-repo}" >&2; exit 1; }
fi

OUT="${ROOT}/channel/cicada-stable-${STAMP}.pkglist.txt"
if [[ "${SRC}" == *.txt ]]; then
  cp "${SRC}" "${OUT}"
elif [[ "${SRC}" == *.db.tar.* ]]; then
  command -v bsdtar >/dev/null || { echo "channel-snapshot: bsdtar required to read ${SRC}" >&2; exit 1; }
  # %VERSION% carries the epoch; the filename may not (GitHub rewrites ':'), so
  # read the version from the database fields rather than parsing filenames.
  bsdtar -xOf "${SRC}" 2>/dev/null \
    | awk '/^%NAME%$/{getline n} /^%VERSION%$/{getline v; print n" "v}' \
    | sort -u > "${OUT}"
  [[ -s "${OUT}" ]] || { echo "channel-snapshot: ${SRC} named no packages" >&2; rm -f "${OUT}"; exit 1; }
else
  echo "pass a repo dir, a cicada-stable.db.tar.*, or a pkglist from the ISO build." >&2
  echo "example: docker cp <ctr>:/work/mkarchiso/iso/cicada/pkglist.x86_64.txt ${OUT}" >&2
  exit 1
fi
printf '%s\n' "cicada-stable-${STAMP}" > "${ROOT}/channel/CURRENT"
echo "pinned ${OUT} ($(wc -l < "${OUT}" | tr -d ' ') packages)"
