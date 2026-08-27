# Hardware support

**Device one (prototype):** Intel MacBook Air 2015–2017 (Broadcom BCM4360 → `broadcom-wl`, Apple EFI).

## Broadcom Wi‑Fi (MBA and similar)

This is the Phase‑1 boot/associate path. It is wired in the tree; confirm on the Air with the checklist below.

### What the image ships

| Piece | Why |
|---|---|
| Default live / fallback boot: stock `linux` | `broadcom-wl` is an out-of-tree module; `linux-hardened` + lockdown blocks it |
| Etched default: `linux-hardened` + lockdown | Prefer hardened when Wi‑Fi works on in-tree drivers; MBA picks **Cicada.OS (Wi‑Fi / Broadcom)** = stock `linux` |
| Packages: `broadcom-wl`, `linux-firmware-broadcom` | Driver + firmware blobs |
| NetworkManager + **wpa_supplicant** (not iwd) | `wl` cannot be driven by iwd |
| `wifi.scan-rand-mac-address=no`, cloned MAC **permanent** | Random scan / MAC breaks associate on this chip |
| Do **not** blacklist `brcmfmac` | BCM43602 Airs need the in-tree driver; `wl` is for BCM4360 |

Dock **WIFI** / Super+N opens the Cicada Wi‑Fi picker (`cicada-wifi` → NM). No hidden keybind exam.

### Air smoke checklist (human)

1. Boot the live ISO with the default / Broadcom entry (not only hardened).
2. Click dock **WIFI** (or Super+N), associate to a known SSID.
3. Open Helium; load a page.
4. After `cicada-install`, confirm the **Wi‑Fi / Broadcom** boot entry exists and still associates.
5. Record pass/fail in `docs/test-results.md` (Wi‑Fi row).

### Known limits

- WPA3 on `wl` is weak / often fails — prefer WPA2 for the Air.
- This is not a Graphene-class radio story; telemetry stays off regardless.

## Will it run on other Arch-capable machines?

**Yes, mostly** — Cicada is Arch + a product layer. Anything that boots Arch x86_64 can usually boot the ISO and etch.

| Class | Expectation |
|---|---|
| Framework / ThinkPad / generic Intel+AMD NVMe | First-class etch path (`--internal` for internal NVMe). Wi-Fi via in-tree drivers. TPM2 enroll can work. |
| Other Broadcom Wi-Fi laptops | Same `wl` / firmware / NM+wpa path as the Air; WPA3 still weak. |
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
