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

## Non-claims

Do not market Cicada on an MBA as "as secure as GrapheneOS." Market it as Graphene-*intent* with laptop-honest guarantees.
