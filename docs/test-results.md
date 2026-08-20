# Tier 1 test results

Hardware under test: Intel MacBook Air 2015–2017 live USB unless noted.

| Test | Result | Date | Notes |
|---|---|---|---|
| Live ISO boots to Hyprland + left dock + Waybar | pending | 2026-08-13 | this ISO |
| Wi-Fi: click dock / Super+N, associate, browse | pending | | radios start blocked on purpose |
| Wallpaper visible; Kitty translucent | pending | | |
| `ldd`/`LD_PRELOAD` on Chromium shows hardened_malloc | pending | | GrapheneOS tag 14 built in ISO Docker; live wrapper preloads; global preload on installed |
| Doom under `cicada-run` (Chocolate Doom 3.1.1 + Freedoom 0.13.0) | pass | _confirm_ | Played on hardware. `cicada-doom` execs `cicada-run org.cicada.doom`, so this is the only end-to-end evidence that a demanding GPU + audio + input application actually works inside a bwrap scope with the seccomp filter loaded. Worth more than the game. **Fill in the date/machine.** |
| Mac preflight (`tests/preflight.sh`) | pass | 2026-08-12 | assemble, seal chain+tamper, profile dir mode, JSON policy, cicada-crypt/copytoram strings |
| Start here / FIRST-BOOT.txt in live profile | pass | 2026-08-12 | assemble copies `docs/USER.md` |
| Duress LUKS slot timing | pending | | enroll after `cicada-install`; live USB has no LUKS |
| nftables inbound drop (no ssh) | pending | | `sshd` masked |
| USB insert while unlocked | pending | | usbguard apply-policy |
| USB insert while hyprlock | pending | | InsertedDevicePolicy=block |
| `cicada-vpn on` without wg0.conf fails closed, Wi-Fi still works | pending | | |
| Kill switch: `cicada-vpn on` then `ip link del wg0`; tcpdump on wlan0 shows no leak | pending | | needs a real endpoint |
| Locked 30 min reboot-to-rest | pending | | timer 1 min; default 1800s. Set `CICADA_LOCK_REBOOT_SEC=60` to test |
| `cicada-seal verify` after boot/lock/wifi events | pending | | next ISO; `tests/seal.sh` passes on the builder |
| Amnesic USB forgets session (`tests/amnesic-verify.sh`) | procedure | 2026-08-13 | static wiring pass on Mac; bulk_extractor/strings scan after an Air canary session |
| LUKS2 pull-the-drive | n/a live | | install-time |
| TPM2 fail-to-passphrase | n/a live | | MBA Apple EFI: no Cicada TPM story |
| sbctl re-sign pacman hook | n/a until enrolled | | hook no-ops if sbctl not installed/enrolled |

`tests/tirimid.sh` checks only that Doom is *wired* — the launcher, the icon, the
lockfile pin, the SDL2 dependency. It does not launch anything. The row above is
hardware evidence and is not reproducible by the suite; do not let a green test
run be mistaken for it.

Fail closed: VPN without config does not enable the kill switch. Kernel default on this ISO is `linux` so Broadcom Wi-Fi works; hardened is an explicit boot choice.
