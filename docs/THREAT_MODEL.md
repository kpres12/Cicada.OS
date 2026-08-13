# Cicada.OS Threat Model

## Goals

- Hostile privacy defaults (no telemetry, minimal phoning home)
- Compartmentalized profiles (Graphene-like UX; lighter than Qubes)
- Daily-driver usability with a locked, distinctive shell
- Honest security claims tied to hardware capability

## In scope (v0–v1)

- Network / telemetry abuse reduction
- Drive-by browser compromise containment (sandbox + profiles)
- Disk encryption at rest (LUKS)
- Casual physical access (lock screen, encrypted volumes)
- User error (radios on, leaky browser defaults)

## Out of scope (for MBA-class hardware)

- Evil maid with firmware implant (no trustworthy measured boot on Apple EFI)
- PIN brute-force resistance equivalent to Titan M2
- Intel ME neutralization guarantees
- Nation-state firmware interdiction

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
