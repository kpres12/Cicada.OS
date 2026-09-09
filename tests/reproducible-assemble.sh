#!/usr/bin/env bash
# Prove the assemble stage is reproducible: same commit, same SOURCE_DATE_EPOCH,
# same profile tree byte-for-byte. Run on the Mac (or CI) in seconds, no root.
#
# This is NOT the full "Reproducible build CI" item on docs/ROADMAP.md — that
# means mkarchiso producing a bit-identical squashfs/ISO, which needs a real
# Linux build (privileged Docker, ~an hour, several GB) and is not run here.
# What this proves is the half that is cheap to check on every push: nothing
# in assemble-profile.sh itself — wall-clock timestamps, unpinned $RANDOM,
# directory-listing order, anything — leaks nondeterminism into the tree
# mkarchiso is handed. If this fails, the expensive full build is guaranteed
# to fail reproducibility too; if it passes, the expensive build still might
# not (mkarchiso/squashfs/xorriso have their own timestamp and ordering
# surface), which is exactly why that remains a separate, heavier check.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

manifest() {
  # F <path> <sha256> for regular files, L <path> -> <target> for symlinks.
  # Symlinks are reported by target string, not followed — several dangling
  # runtime-package symlinks in the overlay point at files that only exist
  # once mkarchiso pacstraps the real package, and that is expected here.
  local dir="$1"
  ( cd "${dir}" && find . \( -type f -o -type l \) -print0 \
      | while IFS= read -r -d '' f; do
          if [[ -L "${f}" ]]; then
            printf 'L %s -> %s\n' "${f}" "$(readlink "${f}")"
          else
            printf 'F %s %s\n' "${f}" "$(shasum -a256 "${f}" | cut -d' ' -f1)"
          fi
        done | sort )
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
epoch="$(git -C "${ROOT}" log -1 --format=%ct 2>/dev/null || echo 1700000000)"

echo "==> assemble twice at SOURCE_DATE_EPOCH=${epoch}"
SOURCE_DATE_EPOCH="${epoch}" CICADA_PROFILE_DIR="${tmp}/a" \
  bash "${ROOT}/iso/assemble-profile.sh" >"${tmp}/a.log" 2>&1 \
  || { tail -20 "${tmp}/a.log"; die "assemble (run a)"; }
SOURCE_DATE_EPOCH="${epoch}" CICADA_PROFILE_DIR="${tmp}/b" \
  bash "${ROOT}/iso/assemble-profile.sh" >"${tmp}/b.log" 2>&1 \
  || { tail -20 "${tmp}/b.log"; die "assemble (run b)"; }

if [[ "${fail}" -eq 0 ]]; then
  manifest "${tmp}/a" > "${tmp}/a.manifest"
  manifest "${tmp}/b" > "${tmp}/b.manifest"
  if diff -u "${tmp}/a.manifest" "${tmp}/b.manifest" > "${tmp}/manifest.diff"; then
    say "two independent assembles at the same epoch are byte-identical ($(wc -l < "${tmp}/a.manifest" | tr -d ' ') entries)"
  else
    head -30 "${tmp}/manifest.diff"
    die "assemble is not deterministic — see diff above"
  fi

  built_a="$(grep '^built=' "${tmp}/a/airootfs/usr/share/cicada/BUILD-ID" || true)"
  built_b="$(grep '^built=' "${tmp}/b/airootfs/usr/share/cicada/BUILD-ID" || true)"
  [[ "${built_a}" == "${built_b}" ]] || die "BUILD-ID built= differs despite pinned SOURCE_DATE_EPOCH"
fi

[[ "${fail}" -eq 0 ]] && echo "REPRODUCIBLE-ASSEMBLE OK"
exit "${fail}"
