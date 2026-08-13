#!/usr/bin/env bash
# Local check of cicada-seal (hash chain + Ed25519). Skip if openssl cannot do ED25519.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEAL="${ROOT}/packages/cicada-defaults/files/usr/local/bin/cicada-seal"
if ! openssl genpkey -algorithm ED25519 >/dev/null 2>&1; then
  echo "skip: openssl has no ED25519"
  exit 0
fi
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export CICADA_SEAL_DIR="${tmp}"
python3 "${SEAL}" init >/dev/null
python3 "${SEAL}" append rf.block '{}' >/dev/null
python3 "${SEAL}" append wifi.connect '{"ssid":"test"}' >/dev/null
python3 "${SEAL}" verify
python3 "${SEAL}" pubkey >/dev/null
# Tamper must fail
python3 - "${tmp}/seal.jsonl" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
lines[1] = lines[1].replace("rf.block", "rf.unblock")
p.write_text("\n".join(lines) + "\n")
PY
if python3 "${SEAL}" verify >/dev/null 2>&1; then
  echo "tamper was not detected"
  exit 1
fi
echo "tamper detected (expected)"
