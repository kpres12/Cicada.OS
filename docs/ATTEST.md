# Pixel as attestation root

This is not Graphene Auditor. It is “hardware I already trust (the Pixel) vouches for the laptop.”

## Every machine (including MBA)

```
cicada-attest
```

Writes `~/cicada-attest/device.pub` (Ed25519 from `cicada-seal`) plus a tip of the hash chain. Copy `device.pub` onto a Graphene Pixel you own (locked profile, password manager, or a note). Later `cicada-seal verify` on the laptop; the Pixel still holds the pin if an evil maid rewrote the disk key.

## Machines with TPM2 (Framework, ThinkPad, Librem)

`cicada-attest` also writes `quote.msg` / `quote.sig` / `quote.ak.pub` over PCR 0,1,2,3,7.

On a trusted Linux (this laptop is fine if you just produced the quote):

```
cicada-quote-verify ~/cicada-attest
```

That is `tpm2_checkquote`. After `cicada-tpm-enroll`, a firmware/bootloader change fails TPM unwrap and you type the LUKS passphrase. A quote that does not match the Pixel pin is the Auditor-shaped signal.

Apple EFI: no TPM2. Pubkey pin only. Expected.
