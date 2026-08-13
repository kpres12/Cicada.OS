# Attacks Cicada must answer

GrapheneOS vs forensic tools (Cellebrite / GrayKey / MSAB, reporting through 2025–2026) is the methodology proof: **not “the crypto broke.”** Successes were old builds or the owner unlocking. The arms race is keeping the device in AFU (keys in RAM) and **suppressing** auto-reboot / USB / network wipe — Inseyets Safeguard Mode, GrayKey Preserve.

Laptop attacks are the same primitives. Cicada answers them in software where the silicon allows. **Apple EFI MBA cannot match Titan M2 + verified boot.** That is a hardware tier, not a missed conf file.

## Forensic lesson (phones → laptops)

| Graphene fact | Cicada implication |
|---|---|
| Locked current Graphene listed no-access in leaked Cellebrite matrices (post-~2022 patches) | Do not claim the same for Cicada on an MBA |
| AFU vs BFU is the state that matters | Power-off / reboot-to-rest returns LUKS to rest. **Speed before an adversary can inhibit systemd** |
| USB lockdown when locked does real work | `cicada-lock` + USBGuard `InsertedDevicePolicy=block` |
| Auto-reboot is only as good as how fast it fires | Default locked reboot is **30 min**, not 6h. Override `CICADA_LOCK_REBOOT_SEC` |
| No public break of AES / KDF / verified boot on current Graphene | We do not invent “Cicada-grade crypto.” We use LUKS2 Argon2id and fail closed |

## Attack matrix

| Attack | Countermeasure | MBA 2015–2017 | Status |
|---|---|---|---|
| Trackers / telemetry | Hostile defaults, Chromium policy, NM probe off | Yes | Partial (live) |
| Browser 0-day | Helium + JIT-off later; v0 Chromium + `cicada-run` net deny | Yes | Partial |
| VPN leak | `cicada-vpn` nftables kill switch + `tests/killswitch.sh` | Yes | Code; needs endpoint |
| Supply chain (AUR) | Official repos only; `docs/aur-audit.md` | Yes | Policy |
| LUKS brute force | LUKS2 **Argon2id**; TPM2 lockout on machines that have a real TPM | Weak/no SE | Argon2id + boot attempt cap (default 20 → `luksErase`); no Titan-class throttle |
| Evil maid (bootkit) | Secure Boot + measured boot (sbctl / Heads) | **No** (Apple EFI) | Hook no-ops until enrolled; Heads = tier 3 |
| Cold boot (RAM remnant) | `init_on_free=1`; reboot-to-rest; TME/SME where CPU has it | Broadwell: no TME | Cmdline + timer; not RAM encryption |
| DMA / Thunderbolt | `intel_iommu=on iommu.passthrough=0`; USBGuard when locked | Air has no TB3; VT-d if firmware allows | Cmdline + lock USB |
| Kernel memory bugs | `linux-hardened` entry, lockdown on that entry, CFI in that kernel | Yes as **opt-in** boot | Default `linux` so `broadcom-wl` works |
| `hardened_malloc` | Graphene allocator | AUR only | Wrapper no-op until audit |
| Keylogger (software) | Wayland, not X11 | Yes | Hyprland |
| Keylogger (inline hardware) | Physical | Out of scope | — |
| Auto-reboot suppress | Short timer + `reboot --force`; USB blocked so gadget DMA is harder | Userspace can still be raced | 30 min + USB lock; not a secure element |

## Cicada extras (what we can do without Pixel silicon)

- Device Ed25519 key + SHA-256 hash-chained seal log (`cicada-seal`) on boot, lock, RF, Wi-Fi, VPN
- `cicada-auth confirm` for install / VPN-off / duress-enroll (not Wi-Fi clicks)
- `cicada-attest`: TPM2 quote if present; otherwise export device pubkey for a Graphene Pixel to pin (`docs/ATTEST.md`)
- `cicada-beacon`: Meshtastic duress text of the seal tip; exit 2 if no radio
- Randomized MAC (NetworkManager + iwd), Chromium 3P cookies / WebRTC / Privacy Sandbox / Google DoH denied by policy; JIT/WebGPU off as recommended (overridable)

Cellebrite-class “no extraction from locked current Graphene” is **not** a Cicada-on-MBA claim. Same methodology, weaker hardware. Tier 3 (Librem / NitroPad + Heads) is where evil maid gets a real answer.
