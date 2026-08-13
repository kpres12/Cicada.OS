# Pixel as attestation root

MBA 2015–2017 has no trustworthy TPM2. The device Ed25519 key from `cicada-seal pubkey` is the laptop identity.

1. On the laptop: `cicada-attest` (prints pubkey; TPM quote only if `/dev/tpmrm0` exists).
2. On a Graphene Pixel you own: store that pubkey (password manager / Auditor notes / a file in a locked profile).
3. Later Framework-class machines: `tpm2_quote` over PCR 0,1,2,3,7; Pixel checks quote + still pins the same Cicada device key for the seal log.

This is not Graphene Auditor. It is “hardware I already trust (the Pixel) vouches for the laptop’s logs.”
