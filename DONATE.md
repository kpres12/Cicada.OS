# Supporting Cicada.OS

Cicada.OS is open source with no company behind it. Donations are optional, carry
no perk, no token and no vote, and nothing is owed in return. The software is free
either way.

If you would rather wait until Cicada is worth trusting, that is the more sensible
choice — it is **pre-alpha**, and the front page says why.

## What it funds

The biggest limit on this project is not code, it is **hardware**. Most of the
hardening is verified structurally or on a Linux kernel in a container; a real
chunk of it cannot be answered anywhere but on a physical machine — whether a
chipset watchdog resets a given board, whether a kernel actually refuses a USB
device at `authorized_default=0`, whether a LoRa radio carries a beacon.

- TPM2 + Secure Boot laptops, to move claims off the "needs the machine" list
- LoRa hardware for `cicada-beacon`, which is currently unproven
- Hosting for the signed `cicada-stable` package mirror

## Addresses

| Chain | Network | Address |
|---|---|---|
| Bitcoin | mainnet, native segwit (bech32 / P2WPKH) | `bc1qkp3dpjquzasa9yv9lz4rfpqnuwy89qun8gk74c` |
| Ethereum | mainnet (ERC-20 on mainnet also fine) | `0xC40B098D8804A5e8310bC0dE7786672Ae40D5a74` |
| Solana | mainnet-beta | `9LySYH4F9RGP8xNrKGvXQnfgtk1nZc3td21LeyEQnYTd` |

## Verify before sending

A donation page is worth compromising, and one altered character sends your money
to a stranger with no way back. Do not trust a rendered page because it looks
right. Every address above carries its own checksum and your wallet checks it for
free:

- **BTC** — bech32 checksum. A wallet refuses a mistyped `bc1…` rather than sending.
- **ETH** — EIP-55: the *mixed upper/lowercase* **is** the checksum. Do not lowercase it.
- **SOL** — base58 decoding to exactly 32 bytes. A wallet rejects anything else.

This file and <https://kpres12.github.io/Cicada.OS/donate/> must agree. This one is
covered by git history, so it is the one to diff against. **If they ever disagree,
trust neither and open an issue** — that disagreement is what a compromise looks
like. Send a small amount first regardless.

`tests/donate.sh` re-derives all three checksums from this file and fails if the
site and this table drift apart.
