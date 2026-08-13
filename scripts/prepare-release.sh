#!/usr/bin/env bash
# Prepare a public-beta GitHub Release from out/*.iso
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${CICADA_OUT:-${ROOT}/out}"

iso="$(ls -1t "${OUT}"/cicada-*.iso 2>/dev/null | head -1 || true)"
if [[ -z "${iso}" ]]; then
  echo "No ISO in ${OUT}. Build first (scripts/build-iso-docker.sh or iso/build.sh)." >&2
  exit 1
fi

base="$(basename "${iso}" .iso)"
# cicada-2026.08.13-x86_64 → 2026.08.13
ver="$(sed -n 's/^cicada-\([0-9.]*\)-x86_64$/\1/p' <<<"${base}")"
[[ -n "${ver}" ]] || ver="$(date -u +%Y.%m.%d)"
tag="v${ver}-beta"

sum="${iso}.sha256"
shasum -a 256 "${iso}" | tee "${sum}"
echo
echo "==> release candidate"
echo "    ISO  ${iso}"
echo "    SUM  ${sum}"
echo "    TAG  ${tag}"
echo
echo "Dry-run checks:"
bash "${ROOT}/tests/here.sh" >/tmp/cicada-release-here.log 2>&1 && echo "    here.sh OK" || {
  echo "    here.sh FAILED — see /tmp/cicada-release-here.log" >&2
  exit 1
}
echo
cat <<EOF
Publish with:

  gh release create "${tag}" \\
    --title "Cicada.OS ${ver} (public beta)" \\
    --notes-file "${ROOT}/docs/release-notes-beta.md" \\
    "${iso}" "${sum}"

Then confirm: https://github.com/kpres12/Cicada.OS/releases/latest
Site download button already points there.
EOF
