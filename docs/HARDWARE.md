# Hardware support

**Device one (prototype):** Intel MacBook Air 2015–2017 (Broadcom BCM4360 → `broadcom-wl`, Apple EFI).

## Will it run on other Arch-capable machines?

**Yes, mostly** — Cicada is Arch + a product layer. Anything that boots Arch x86_64 can usually boot the ISO and etch.

| Class | Expectation |
|---|---|
| Framework / ThinkPad / generic Intel+AMD NVMe | First-class etch path (`--internal` for internal NVMe). Wi-Fi via in-kernel drivers. TPM2 enroll can work. |
| Other Broadcom Wi-Fi laptops | Same `wl` / firmware story as the Air; WPA3 still weak. |
| NVIDIA | Untested. Hyprland + NVIDIA is a known footgun; not a Cicada promise yet. |
| Apple Silicon | **No.** ISO is x86_64 only. |
| Apple T2 Intel Macs | Boot/firmware story differs; not the prototype. Don’t claim MBA results. |

## What adapts automatically

- Kernel + firmware from Arch (GPU, NVMe, most Wi-Fi).
- NetworkManager + wpa_supplicant (not iwd — Broadcom needs it; Intel works too).
- LUKS/btrfs etch, greetd login, Helium, scopes — hardware-agnostic.

## What stays MBA-honest

- No Graphene-class boot attestation / Titan / MTE claims on Apple EFI.
- Secure Boot (`sbctl`) may no-op on Apple firmware.
- Wi-Fi MAC randomization defaults to **permanent** because `wl` breaks otherwise (other NICs can tighten later).

## Bottom line

Cicada is **not** MBA-only software. The Air is the dogfood device. Other Arch-class x86_64 hardware is in scope; we harden and document per device as we touch it — we do not pretend every laptop is Graphene.
