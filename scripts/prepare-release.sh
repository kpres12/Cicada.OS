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
# Two different numbers that used to be one, which is why a 1983 MiB ISO would
# still have been split into parts nobody needed to reassemble:
#   SPLIT_ABOVE_MIB  when splitting becomes necessary at all — GitHub's actual
#                    per-asset ceiling is 2 GiB, so anything under that ships as
#                    a single file the user can drag straight into Etcher.
#   PART_MIB         how big each chunk is *if* we have to split.
SPLIT_ABOVE_MIB="${CICADA_SPLIT_ABOVE_MIB:-2048}"
SPLIT_ABOVE_BYTES=$((SPLIT_ABOVE_MIB * 1024 * 1024))
PART_MIB="${CICADA_PART_MIB:-1800}"

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

# --- signature ---------------------------------------------------------------
#
# A published sha256 authenticates nothing on its own. Whoever can serve the ISO
# can serve a matching hash next to it, so the hash only protects against a
# corrupted download — never against a substituted one. The signature is what
# makes the download verifiable.
#
# We sign the .sha256 rather than the 3 GiB image: SHA-256 already binds the
# hash file to the exact bytes of the ISO, and the downloader reassembles from
# parts anyway, so signing the small file is the same guarantee in the shape the
# download instructions already use.
#
# The verifying key CANNOT be the copy that ships inside the ISO — that copy is
# authenticated by the thing it is supposed to authenticate. It is published
# separately (release asset + site) and pinned by fingerprint.
KEYS="${ROOT}/channel/keys"
export GNUPGHOME="${KEYS}/gnupg"
sig_ok=0
fpr=""
if command -v gpg >/dev/null 2>&1 && [[ -d "${GNUPGHOME}" ]] \
   && gpg --list-secret-keys "stable@cicada.os" >/dev/null 2>&1; then
  echo "==> signing ${name}.sha256"
  rm -f "${name}.sha256.asc"
  # -o is not optional: --armor alone writes <file>.asc while the rest of this
  # script would go looking for <file>.sig, and the release would ship with the
  # signature asset missing entirely.
  gpg --batch --yes --armor --detach-sign -o "${name}.sha256.asc" \
      --default-key "stable@cicada.os" "${name}.sha256"
  gpg --armor --export "stable@cicada.os" > "cicada-stable.pub"
  fpr="$(gpg --with-colons --fingerprint "stable@cicada.os" \
         | awk -F: '/^fpr:/{print $10; exit}')"
  # Verify with the exported public key alone, in a throwaway keyring. Signing
  # and then verifying with the secret key still present proves only that gpg
  # ran; this proves the artefacts we are about to publish actually check out
  # against the key a downloader will have.
  vhome="$(mktemp -d)"
  if GNUPGHOME="${vhome}" gpg --batch --quiet --import "cicada-stable.pub" 2>/dev/null \
     && GNUPGHOME="${vhome}" gpg --batch --quiet --verify \
          "${name}.sha256.asc" "${name}.sha256" 2>/dev/null; then
    echo "    signature verifies against the published pubkey alone"
    sig_ok=1
  else
    echo "error: the signature does not verify against cicada-stable.pub" >&2
    rm -rf "${vhome}"
    exit 1
  fi
  rm -rf "${vhome}"
  assets+=("${name}.sha256.asc" "cicada-stable.pub")
  echo "    key ${fpr}"
fi

if [[ "${sig_ok}" != 1 ]]; then
  if [[ "${CICADA_ALLOW_UNSIGNED:-0}" == "1" ]]; then
    echo "!!  publishing UNSIGNED (CICADA_ALLOW_UNSIGNED=1) — downloaders can only" >&2
    echo "!!  detect corruption, not substitution." >&2
  else
    cat >&2 <<'ERR'
error: no signing key, so this release would be unverifiable.

  An ISO published with only a sha256 is authenticated by nothing: an attacker
  who can replace the image can replace the hash beside it.

  Restore channel/keys/gnupg from backup (same key the channel is signed with,
  so machines already trust it), or set CICADA_ALLOW_UNSIGNED=1 to publish a
  release that downloaders cannot verify.
ERR
    exit 1
  fi
fi

if (( size <= SPLIT_ABOVE_BYTES )); then
  echo "==> ISO is $((size / 1024 / 1024)) MiB — fits GitHub's ${SPLIT_ABOVE_MIB} MiB asset limit"
  echo "    Shipping as ONE file: no .part-* and no reassembly step for the user."
fi

if (( size > SPLIT_ABOVE_BYTES )); then
  echo "==> ISO is $((size / 1024 / 1024)) MiB — over the ${SPLIT_ABOVE_MIB} MiB asset limit"
  echo "    Splitting into ${PART_MIB} MiB parts. Every downloader now has to \`cat\` them"
  echo "    back together before they can flash, which is the first step of the install"
  echo "    and the one most likely to lose people. Prefer shrinking the image."
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
  reassemble="  cat ${name}.part-* > ${name}"
else
  assets+=("${name}")
  # Printing a reassembly step for an ISO that was never split sends the
  # downloader looking for .part-* files the release does not contain.
  reassemble=""
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
    --title "Cicada.OS ${ver} (pre-alpha)" \\
    --notes-file "${ROOT}/docs/release-notes-beta.md" \\${asset_lines}

Re-publishing an existing tag (same-day rebuild) instead:

  gh release upload "${tag}"${asset_flat} --clobber

Then confirm: https://github.com/kpres12/Cicada.OS/releases/latest
Site download button already points there.

Downloader path this produces:
  gpg --import cicada-stable.pub
  gpg --fingerprint stable@cicada.os      # must equal the fingerprint below
  gpg --verify ${name}.sha256.asc ${name}.sha256
${reassemble:+${reassemble}
}  shasum -a 256 -c ${name}.sha256

Signing key fingerprint (publish this on the site, NOT only in the release):
  ${fpr:-<unsigned release>}

The signature step is the one that matters. A pubkey shipped next to the thing
it signs proves only that both came from the same place, so the fingerprint has
to reach the downloader by a second route or the whole chain is decorative.
EOF
