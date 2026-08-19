#!/usr/bin/env bash
# cicada-beacon / cicada-link: sign, deliver, and — the part that matters —
# actually fire on a boot chain that changed.
#
# In the spirit of tests/seccomp.sh rather than tests/here.sh: this does not
# grep the source for a string, it builds a fake EFI system partition, edits the
# kernel command line the way an evil maid would, and fails if the witness does
# not raise the alarm.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ROOT}/packages/cicada-defaults/files/usr/local/bin"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

if ! openssl genpkey -algorithm ED25519 >/dev/null 2>&1; then
  echo "skip: openssl has no ED25519"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export CICADA_SEAL_DIR="${tmp}/seal"
export CICADA_BEACON_CONF="${tmp}/beacon.conf"
export CICADA_ESP="${tmp}/esp"
export PATH="${BIN}:${PATH}"
mkdir -p "${CICADA_SEAL_DIR}" "${CICADA_ESP}/loader/entries" "${CICADA_ESP}/EFI/Linux"
echo "TRANSPORTS=stdout" > "${CICADA_BEACON_CONF}"
printf 'options root=/dev/sda2 rw quiet\n' > "${CICADA_ESP}/loader/entries/cicada.conf"
printf 'MZ-not-really-a-pe' > "${CICADA_ESP}/EFI/Linux/cicada.efi"

python3 "${BIN}/cicada-seal" init >/dev/null

echo "==> identity"
python3 "${BIN}/cicada-link" show >/dev/null || die "cicada-link show"
fp="$(python3 "${BIN}/cicada-link" show | awk '/^  fingerprint/{print $2; exit}')"
[[ "${fp}" =~ ^[0-9a-f]{4}(-[0-9a-f]{4}){5}$ ]] \
  && say "fingerprint is six readable groups (${fp})" \
  || die "fingerprint shape: ${fp}"

key="$(python3 "${BIN}/cicada-link" show | awk '/^  key/{print $2; exit}')"
printf '%s' "${key}" > "${tmp}/peer.b64"
python3 "${BIN}/cicada-link" add pixel "${tmp}/peer.b64" >/dev/null || die "link add"
python3 "${BIN}/cicada-link" list | grep -q pixel && say "witness pinned" || die "link list"
# Re-pinning the same name to a different key must be refused, not silently
# accepted: that is how a witness gets replaced by what it was meant to detect.
python3 - "${tmp}/other.b64" <<'PY'
import base64, os, sys
open(sys.argv[1], "w").write(base64.b64encode(os.urandom(32)).decode())
PY
if python3 "${BIN}/cicada-link" add pixel "${tmp}/other.b64" >/dev/null 2>&1; then
  die "re-pinning a witness to a different key was allowed"
else
  say "re-pinning a pinned name is refused"
fi

echo "==> statement round trip"
tok="$(python3 "${BIN}/cicada-beacon" posture | head -1)"
[[ "${tok}" == CIC1:* ]] && say "token is tagged CIC1" || die "token prefix: ${tok:0:16}"
# 29-byte body + 64-byte signature, base64url without padding.
len="${#tok}"
[[ "${len}" -le 200 ]] \
  && say "token is ${len} chars — fits one Meshtastic text packet" \
  || die "token is ${len} chars, will not fit a LoRa packet"

python3 "${BIN}/cicada-beacon" verify "${tok}" >/dev/null \
  && say "first statement verifies (no history yet)" \
  || die "verify of a fresh statement"

# The compact token and the JSON statement must describe the same machine. They
# are produced from one collection pass; if the packer ever re-reads the system
# instead, `show` starts printing a statement the token does not attest to.
shown="$(python3 "${BIN}/cicada-beacon" show)"
stok="$(grep -o 'CIC1:[A-Za-z0-9_-]*' <<<"${shown}" | head -1)"
sjson="$(sed -n '1,/^}$/p' <<<"${shown}")"
sesp="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["boot"]["esp"][:16])' <<<"${sjson}")"
vout="$(python3 "${BIN}/cicada-beacon" verify "${stok}" 2>&1 || true)"
vboot="$(awk '/^boot hash/{print $3}' <<<"${vout}" | tr -d '…')"
[[ "${sesp}" == "${vboot}"* ]] \
  && say "token and JSON statement agree on the boot hash" \
  || die "token says ${vboot}, statement says ${sesp}"

echo "==> tamper"
bad="${tok:0:40}$( [[ "${tok:40:1}" == "A" ]] && echo B || echo A )${tok:41}"
if python3 "${BIN}/cicada-beacon" verify "${bad}" >/dev/null 2>&1; then
  die "a flipped byte still verified"
else
  say "flipped byte fails the signature"
fi

echo "==> evil maid"
# The whole point. Edit the kernel command line on the plaintext ESP the way an
# attacker with a screwdriver would, and require the witness to notice.
printf 'options root=/dev/sda2 rw quiet init=/bin/sh\n' > "${CICADA_ESP}/loader/entries/cicada.conf"
tok2="$(python3 "${BIN}/cicada-beacon" posture | head -1)"
rc=0
out="$(python3 "${BIN}/cicada-beacon" verify "${tok2}" 2>&1)" || rc=$?
if [[ "${rc}" -eq 3 ]] && grep -q "BOOT CHAIN CHANGED" <<<"${out}"; then
  say "cmdline edit on the ESP raises the alarm (exit 3)"
else
  die "evil maid edit was not detected (rc=${rc})"
fi

echo "==> duress"
rc=0
tok3="$(python3 "${BIN}/cicada-beacon" duress | head -1)"
out="$(python3 "${BIN}/cicada-beacon" verify "${tok3}" 2>&1)" || rc=$?
[[ "${rc}" -eq 3 ]] && grep -q DURESS <<<"${out}" \
  && say "duress statement alarms" || die "duress not flagged (rc=${rc})"

echo "==> no transport is not a success"
# "file" with no BEACON_FILE configured is a transport that cannot deliver, and
# it is deterministic on any machine — unlike hiding the meshtastic CLI, which
# depends on what the person running the test happens to have installed.
echo "TRANSPORTS=file" > "${CICADA_BEACON_CONF}"
rc=0
python3 "${BIN}/cicada-beacon" duress >/dev/null 2>&1 || rc=$?
[[ "${rc}" -eq 2 ]] \
  && say "undelivered beacon exits 2, not 0" \
  || die "undelivered beacon exited ${rc} (docs/SEAL.md promises 2)"

echo "==> seal log still verifies after all of that"
python3 "${BIN}/cicada-seal" verify >/dev/null && say "seal chain intact" || die "seal chain"

[[ "${fail}" -eq 0 ]] || { echo "BEACON TESTS FAILED"; exit 1; }
echo "beacon ok"
