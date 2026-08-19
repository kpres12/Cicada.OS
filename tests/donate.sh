#!/usr/bin/env bash
# The donation addresses, checked the way a wallet would.
#
# A donation page is a target: one altered character routes money to somebody
# else, irreversibly, and it is invisible to review because every address looks
# like line noise. So nothing here trusts the strings. Each one is re-derived
# from its own checksum — bech32 for BTC, EIP-55 (keccak-256) for ETH, base58
# length for SOL — and the site and DONATE.md must carry the identical set.
#
# This is cheap insurance against both a typo and a tampered working tree.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
say() { printf '  OK  %s\n' "$*"; }
die() { printf '  FAIL %s\n' "$*"; fail=1; }

PAGE="${ROOT}/site/donate/index.html"
DOC="${ROOT}/DONATE.md"
for f in "${PAGE}" "${DOC}"; do
  [[ -f "${f}" ]] || { die "missing ${f}"; echo "DONATE TESTS FAILED"; exit 1; }
done

echo "==> addresses agree between the page and DONATE.md"
python3 - "${PAGE}" "${DOC}" "${ROOT}/site/assets/svg" <<'PY'
import re, sys, pathlib

page, doc, svgdir = (pathlib.Path(p) for p in sys.argv[1:4])
pt, dt = page.read_text(), doc.read_text()
rc = 0

def grab(text):
    return {
        "BTC": set(re.findall(r"\bbc1[02-9ac-hj-np-z]{6,87}\b", text)),
        "ETH": set(re.findall(r"\b0x[0-9a-fA-F]{40}\b", text)),
        "SOL": set(re.findall(r"\b[1-9A-HJ-NP-Za-km-z]{43,44}\b", text)),
    }

P, D = grab(pt), grab(dt)
for k in ("BTC", "ETH", "SOL"):
    if len(P[k]) != 1:
        print(f"  FAIL page has {len(P[k])} {k} addresses, expected exactly 1: {P[k]}"); rc = 1; continue
    if P[k] != D[k]:
        print(f"  FAIL {k} differs — page {P[k]} vs DONATE.md {D[k]}"); rc = 1; continue
    print(f"  OK  {k} identical in both")

# ---------- bech32 (BIP-173) ----------
CH = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
def polymod(v):
    G = [0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]; c = 1
    for x in v:
        b = c >> 25; c = ((c & 0x1ffffff) << 5) ^ x
        for i in range(5):
            c ^= G[i] if ((b >> i) & 1) else 0
    return c
def bech32_ok(a):
    a = a.lower(); pos = a.rfind("1")
    if pos < 1 or pos + 7 > len(a) or len(a) > 90: return False
    hrp, data = a[:pos], a[pos+1:]
    if any(ch not in CH for ch in data): return False
    d = [CH.index(ch) for ch in data]
    exp = [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp] + d
    return polymod(exp) == 1

# ---------- keccak-256, for EIP-55 ----------
def keccak256(msg):
    RC = [0x0000000000000001,0x0000000000008082,0x800000000000808A,0x8000000080008000,
          0x000000000000808B,0x0000000080000001,0x8000000080008081,0x8000000000008009,
          0x000000000000008A,0x0000000000000088,0x0000000080008009,0x000000008000000A,
          0x000000008000808B,0x800000000000008B,0x8000000000008089,0x8000000000008003,
          0x8000000000008002,0x8000000000000080,0x000000000000800A,0x800000008000000A,
          0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008]
    R = [[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]]
    M = (1 << 64) - 1
    rot = lambda x, n: ((x << (n % 64)) | (x >> (64 - (n % 64)))) & M
    S = [[0]*5 for _ in range(5)]; rate = 136
    m = bytearray(msg); m.append(0x01)
    while len(m) % rate: m.append(0)
    m[-1] ^= 0x80
    for off in range(0, len(m), rate):
        blk = m[off:off+rate]
        for i in range(rate // 8):
            S[i % 5][i // 5] ^= int.from_bytes(blk[i*8:i*8+8], "little")
        for rnd in range(24):
            C = [S[x][0]^S[x][1]^S[x][2]^S[x][3]^S[x][4] for x in range(5)]
            Dd = [C[(x-1)%5] ^ rot(C[(x+1)%5], 1) for x in range(5)]
            for x in range(5):
                for y in range(5): S[x][y] ^= Dd[x]
            B = [[0]*5 for _ in range(5)]
            for x in range(5):
                for y in range(5): B[y][(2*x+3*y)%5] = rot(S[x][y], R[x][y])
            for x in range(5):
                for y in range(5): S[x][y] = B[x][y] ^ ((~B[(x+1)%5][y]) & B[(x+2)%5][y] & M)
            S[0][0] ^= RC[rnd]
    return b"".join(S[i%5][i//5].to_bytes(8, "little") for i in range(25))[:32]

B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

if not rc:
    btc, eth, sol = (next(iter(P[k])) for k in ("BTC", "ETH", "SOL"))

    if bech32_ok(btc): print("  OK  BTC bech32 checksum verifies")
    else: print(f"  FAIL BTC bech32 checksum does NOT verify: {btc}"); rc = 1

    body = eth[2:]
    h = keccak256(body.lower().encode()).hex()
    want = "0x" + "".join(c.upper() if c.isalpha() and int(h[i], 16) >= 8 else c.lower()
                          for i, c in enumerate(body))
    if want == eth: print("  OK  ETH EIP-55 mixed-case checksum verifies")
    else: print(f"  FAIL ETH EIP-55 mismatch\n       have {eth}\n       want {want}"); rc = 1

    n = 0
    for c in sol: n = n * 58 + B58.index(c)
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    if len(raw) == 32: print("  OK  SOL base58 decodes to a 32-byte pubkey")
    else: print(f"  FAIL SOL decodes to {len(raw)} bytes, not 32"); rc = 1

    # The QR is the thing people actually scan. If it drifts from the text, the
    # text being right is no comfort at all.
    import subprocess, shutil
    for tag, addr in (("btc", btc), ("eth", eth), ("sol", sol)):
        f = svgdir / f"qr-{tag}.svg"
        if not f.exists(): print(f"  FAIL missing QR {f.name}"); rc = 1; continue
        if shutil.which("qrencode"):
            got = subprocess.run(["qrencode","-t","SVG","-m","1","-s","4","--level=M","-o","-",addr],
                                 capture_output=True).stdout.decode()
            cur = f.read_text()
            strip = lambda s: re.sub(r"<!--.*?-->", "", s, flags=re.S).strip()
            if strip(got) == strip(cur): print(f"  OK  QR {tag} encodes the current address")
            else: print(f"  FAIL QR {tag} does not match the address it sits next to"); rc = 1
        else:
            print(f"  NOTE qrencode absent — cannot re-derive QR {tag} (install qrencode to check)")

sys.exit(rc)
PY
[[ $? -eq 0 ]] || fail=1

[[ "${fail}" -eq 0 ]] || { echo "DONATE TESTS FAILED"; exit 1; }
echo "donate ok"
