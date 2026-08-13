# Cicada.OS

Arch-based privacy/security laptop OS. GrapheneOS intent, Hyprland daily-driver feel, Helium-style product layer on top of Arch.

**North star:** GrapheneOS-class hostile defaults and profile isolation on laptops — honest about hardware limits.  
**Method:** Arch is the engine. Cicada owns defaults, release channel, shell, and profiles.

## What this is

| Layer | Owner |
|---|---|
| Kernel, packages, rolling base | Arch |
| Hostile defaults, ISO, staged updates | Cicada |
| OT / Evangelion Hyprland shell | Cicada |
| Graphene-like user profiles | Cicada |

## Repo layout

```
iso/                  assemble releng + Cicada overlay, build helper
packages/
  cicada-defaults/    sysctl, firewall, rfkill, VPN hooks
  cicada-shell/       Hyprland rice + session
  cicada-profiles/    profile isolation stubs
vendor/
  archiso/            official Arch live-ISO tooling
  Hyprland/           Hyprland compositor source
docs/                 threat model + roadmap
```

## v0 target

1. Bootable Cicada ISO (Arch remix)
2. Install to **external SSD** on Intel MacBook Air (2015–2017)
3. Hyprland session with Cicada look
4. Privacy defaults: no telemetry, Wi‑Fi/BT off at first boot, firewall on
5. Hardened browser path (Helium/Trivalent when packaged; Chromium fallback in v0)

## Build the ISO

On the M2 Mac (cross-compiles an **Intel/x86_64** image):

```bash
./scripts/build-iso-docker.sh
# → out/cicada-*.iso
```

Details: [docs/BUILD.md](docs/BUILD.md). Flash to USB, boot the MBA with `Option`, install to **external SSD** first.

## Status

Scaffold / pre-alpha. Not a daily driver yet. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Threat model

See [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md), [docs/GRAPHENE_PARITY.md](docs/GRAPHENE_PARITY.md), [docs/SANDBOX.md](docs/SANDBOX.md), and [docs/DESIGN.md](docs/DESIGN.md).
