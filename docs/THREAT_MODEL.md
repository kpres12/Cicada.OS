# Cicada.OS Threat Model

## Goals

- Hostile privacy defaults (no telemetry, minimal phoning home)
- Compartmentalized profiles (Graphene-like UX; lighter than Qubes)
- Daily-driver usability with a locked, distinctive shell
- Honest security claims tied to hardware capability

## In scope (v0–v1)

- Network / telemetry abuse reduction
- Drive-by browser compromise containment (sandbox + profiles)
- Disk encryption at rest (LUKS2 Argon2id)
- Casual physical access (lock screen, USB blocked while locked, reboot-to-rest)
- User error (radios on, leaky browser defaults)
- DMA reduction (IOMMU on) and AFU window reduction (fast reboot-to-rest)

## Out of scope (for MBA-class hardware)

- Cellebrite/GrayKey-class extraction resistance equivalent to current GrapheneOS on Pixel+Titan
- Evil maid with firmware implant (no trustworthy measured boot on Apple EFI)
- PIN brute-force resistance equivalent to Titan M2 (1/day after 140)
- Cold-boot with TME/SME (Broadwell has neither)
- Intel ME neutralization guarantees
- Nation-state firmware interdiction

See [docs/ATTACKS.md](ATTACKS.md) for the forensic/laptop mapping.

## Adversaries

| Adversary | Cicada stance |
|---|---|
| Trackers / adtech | Defeat by default |
| Opportunistic malware | Mitigate via sandbox + defaults |
| Thief with powered-off laptop | LUKS; duress later |
| Evil maid | Best-effort later on Heads/PureBoot hardware only |
| Remote APTs | Reduce blast radius via profiles; not a magic shield |

## Hardware tiers

Cicada is written for a range of machines, and the security ceiling is set by
hardware, not by configuration. The software is identical across tiers; what
changes is which root of trust is available. `cicada-hw-trust` reports the tier
a given machine is actually on.

### Tier 0 — no TPM2, vendor-controlled firmware
*Apple EFI MacBooks (incl. the 2015–2017 Air), most pre-2016 x86.*

- Disk: LUKS2 + Argon2id, **passphrase is the entire boundary**
- Guessing: **not rate-limited**. An imaged disk is attacked offline forever, so
  `cicada-install` generates 80–100 bits rather than accepting a short secret
- Boot: unsigned, unmeasured. **Evil maid is undetectable** — modifying the
  plaintext ESP to capture the passphrase needs a screwdriver, not an exploit
- Optional second factor: `cicada-keyfile-enroll --and` (a USB token you can
  physically not-have)
- Honest summary: **Tails-plus-persistence.** Strong against seizure of a
  powered-off machine, DMA, and network observation. Nothing against firmware.

### Tier 1 — TPM2 present, Secure Boot not user-controlled
*Most OEM laptops with a TPM but locked-down or vendor-keyed firmware.*

- Disk: LUKS2 sealed to TPM2 PCRs 0+7 **behind a PIN** (`cicada-tpm-enroll`)
- Guessing: **rate-limited in hardware.** The TPM's dictionary-attack lockout
  counts failures in silicon and the CPU cannot reset it. This is the property
  that makes a 6-digit PIN safe on a Pixel, and it is the single largest jump
  in the whole table
- Boot: firmware replacement changes PCR 0 → unsealing fails → tamper is
  *visible* instead of silent
- Evil maid: detectable, not prevented

### Tier 2 — TPM2 + user-controlled Secure Boot
*Framework, recent ThinkPad, Star Labs, NovaCustom, System76.*

- Everything in Tier 1, plus:
- Own Secure Boot keys enrolled (`cicada-sbctl-enroll`), so the firmware refuses
  to execute anything you did not sign
- Kernel + initramfs as a signed UKI, measured into PCR 11, and the disk key
  sealed to 0+7+11 — a modified initramfs cannot unseal the disk
- **This is as close to GrapheneOS as commodity x86 gets:** a verified boot
  chain plus hardware-throttled unlock. What is still missing versus a Pixel is
  a discrete secure element holding the key material and per-app hardware
  attestation
- Evil maid: **prevented** for the boot chain, not merely detected

### Tier 3 — Tier 2 + owner-controlled boot firmware
*NitroPad / Librem with Heads or PureBoot, coreboot machines.*

- Everything in Tier 2, plus firmware you can build and measure yourself, with a
  tamper-evident boot that proves itself to you (TOTP / USB token) before you
  type anything
- Removes the "trust the vendor's firmware" assumption that Tiers 1–2 keep

### What no tier fixes
Intel ME / AMD PSP are present in all of them. Traffic analysis defeats Tor at
sufficient scale. A compromised or seized-unlocked endpoint makes every item
above irrelevant.

## Known costs of our own design choices

These are not adversary capabilities; they are prices Cicada pays for decisions
it made on purpose. They belong here so nobody rediscovers them as a surprise.

**btrfs is copy-on-write, so "deleted" is weaker than on ext4.** Overwriting a
file writes new extents and leaves the old ones unreferenced but intact until a
rebalance. Against an adversary who obtains the volume *unlocked* — a coerced
unlock, or an AFU seizure — recovering superseded file contents is materially
easier than it would be on ext4, which zeroes extent pointers on delete. We take
this for snapshots and checksums. If per-file deletion resistance matters more
to you than snapshots, ext4 is the better filesystem for this OS.

**There is no swap, and that is load-bearing.** No swapfile, no zram, no
hibernation. Swap is one of the standard forensic recoveries — key material and
plaintext paged to disk, surviving reboot, out of reach of `init_on_free`.
Adding a swapfile "for performance" would silently undo a real property.
`tests/here.sh` asserts its absence.

**Profiles share one LUKS volume.** Work/burner separation stops a running
process in one profile from reading another's files. It does nothing once the
disk is unlocked: every profile's home is plaintext on the same volume at that
point. Profiles are a blast-radius tool, not an encryption boundary.

**The ESP is plaintext, unsigned and unmeasured.** Evil maid does not need to
touch Apple EFI to win — modifying `/boot`'s initramfs to capture the passphrase
is a screwdriver-and-USB attack with the same outcome. On this hardware there is
no detection for it. This is the softest of the physical-access attacks, not the
most exotic one, and it should be ranked accordingly.

## Non-claims

Do not market Cicada on an MBA as "as secure as GrapheneOS." Market it as Graphene-*intent* with laptop-honest guarantees.
