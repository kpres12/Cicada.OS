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

1. **Prototype (Intel MBA 2015–2017):** privacy + hardening, software only
2. **Daily driver (Framework etc.):** same software, better maintainability
3. **Graphene-adjacent (Librem / NitroPad + Heads/PureBoot):** boot integrity + tamper story

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
