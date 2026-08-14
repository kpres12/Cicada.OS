#!/usr/bin/env bash
# Prepare a public-beta GitHub Release from out/*.iso
#
# Produces exactly the asset set a downloader needs, in the form the download
# page tells them to use:
#   cicada-<ver>-x86_64.iso.part-NN   split, because GitHub caps release assets
#                                     at 2 GiB and the ISO is over 3 GiB
#   cicada-<ver>-x86_64.iso.sha256    bare filename, so `shasum -c` works in
#                                     whatever directory they downloaded into
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${CICADA_OUT:-${ROOT}/out}"

# GitHub rejects release assets over 2 GiB. 1800 MiB keeps a margin and matches
# the parts already published for the first beta.
PART_MIB="${CICADA_PART_MIB:-1800}"
PART_BYTES=$((PART_MIB * 1024 * 1024))

iso="$(ls -1t "${OUT}"/cicada-*.iso 2>/dev/null | grep -v 'cicada-latest' | head -1 || true)"
if [[ -z "${iso}" ]]; then
  echo "No ISO in ${OUT}. Build first (scripts/build-iso-docker.sh or iso/build.sh)." >&2
  exit 1
fi

base="$(basename "${iso}" .iso)"
name="$(basename "${iso}")"
# cicada-2026.08.13-x86_64 → 2026.08.13
ver="$(sed -n 's/^cicada-\([0-9.]*\)-x86_64$/\1/p' <<<"${base}")"
[[ -n "${ver}" ]] || ver="$(date -u +%Y.%m.%d)"
tag="v${ver}-beta"

cd "${OUT}"

# Hash the bare filename, never the path. `shasum -a 256 out/cicada.iso` writes
# "…  out/cicada.iso", and then `shasum -c` on the downloader's machine looks
# for an out/ directory that does not exist and reports FAILED — which reads as
# a corrupt download rather than a packaging mistake.
echo "==> sha256 (${name})"
shasum -a 256 "${name}" | tee "${name}.sha256"

size="$(wc -c < "${name}" | tr -d ' ')"
assets=("${name}.sha256")

if (( size > PART_BYTES )); then
  echo "==> ISO is $((size / 1024 / 1024)) MiB — splitting into ${PART_MIB} MiB parts"
  rm -f "${name}".part-* 2>/dev/null || true
  split -d -a 2 -b "${PART_MIB}m" "${name}" "${name}.part-"
  shopt -s nullglob
  parts=("${name}".part-*)
  (( ${#parts[@]} > 0 )) || { echo "split produced no parts" >&2; exit 1; }

  # Prove the documented reassembly reproduces the ISO before anyone is told to
  # rely on it. A split that does not `cat` back is a silently broken download.
  echo "==> verifying reassembly of ${#parts[@]} parts"
  want="$(shasum -a 256 "${name}" | awk '{print $1}')"
  got="$(cat "${name}".part-* | shasum -a 256 | awk '{print $1}')"
  if [[ "${want}" != "${got}" ]]; then
    echo "error: reassembled parts do not match the ISO (${got} != ${want})" >&2
    exit 1
  fi
  echo "    reassembly OK (${want})"
  assets+=("${parts[@]}")
else
  assets+=("${name}")
fi

echo
echo "==> release candidate"
echo "    ISO    ${iso}"
echo "    TAG    ${tag}"
echo "    ASSETS ${#assets[@]}"
printf '           %s\n' "${assets[@]}"
echo

echo "Dry-run checks:"
bash "${ROOT}/tests/here.sh" >/tmp/cicada-release-here.log 2>&1 && echo "    here.sh OK" || {
  echo "    here.sh FAILED — see /tmp/cicada-release-here.log" >&2
  exit 1
}
echo

# macOS ships bash 3.2, so no ${arr[@]@Q}. Asset names are our own and contain
# no spaces, but quote them anyway so a copy-pasted command stays correct.
asset_lines=""
asset_flat=""
for a in "${assets[@]}"; do
  asset_lines="${asset_lines}"$'\n    '"\"${a}\" \\"
  asset_flat="${asset_flat} \"${a}\""
done
# Drop the trailing backslash-continuation from the last line.
asset_lines="${asset_lines% \\}"

cat <<EOF
Publish with (from ${OUT}):

  gh release create "${tag}" \\
    --title "Cicada.OS ${ver} (public beta)" \\
    --notes-file "${ROOT}/docs/release-notes-beta.md" \\${asset_lines}

Re-publishing an existing tag (same-day rebuild) instead:

  gh release upload "${tag}"${asset_flat} --clobber

Then confirm: https://github.com/kpres12/Cicada.OS/releases/latest
Site download button already points there.

Downloader path this produces:
  cat ${name}.part-* > ${name}
  shasum -a 256 -c ${name}.sha256
EOF
