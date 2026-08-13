# Seal log + signed authorization

Heli.OS pattern: the device key signs high-impact OS actions. Wi-Fi clicks are not prompts.

## `cicada-seal`

Ed25519 device key + SHA-256 hash chain in `/var/lib/cicada/seal.jsonl` (or `~/.local/share/cicada` if that dir is not writable).

```
cicada-seal init
cicada-seal append ACTION ['{"k":"v"}']
cicada-seal verify
cicada-seal pubkey
cicada-seal tip
```

`verify` checks sequence, prev-hash, payload hash, and the Ed25519 signature. Deleting a line or editing a field fails closed.

After `cicada-tpm-enroll` / `cicada-backup` / `cicada-profile dispose`, those actions are also in the chain.

## `cicada-auth confirm ACTION`

Gated: `install`, `vpn.off`, `duress.enroll`. Zenity on the desktop, or type `ALLOW` on a TTY. Result is `auth.allow` / `auth.deny` in the seal log.

Not gated: Wi-Fi, radios, lock, `cicada-beacon` (coercion has to be fast).

## Pixel pin

`cicada-attest` prints the device pubkey when there is no TPM2 (MBA). Store that on a Graphene Pixel. See [ATTEST.md](ATTEST.md).

## Meshtastic

`cicada-beacon` sends `CICADA DURESS <tip>`. No radio → exit 2, still logged. Not a fake success.
