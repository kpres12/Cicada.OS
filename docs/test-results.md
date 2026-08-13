# Tier 1 test results

Hardware under test: Intel MacBook Air 2015–2017 live USB unless noted.

| Test | Result | Date | Notes |
|---|---|---|---|
| Live ISO boots to Hyprland + left dock + Waybar | pending | 2026-08-13 | this ISO |
| Wi-Fi: click dock / Super+N, associate, browse | pending | | radios start blocked on purpose |
| Wallpaper visible; Kitty translucent | pending | | |
| `ldd`/`LD_PRELOAD` on Chromium shows hardened_malloc | pending | | GrapheneOS tag 14 built in ISO Docker; live wrapper preloads; global preload on installed |
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
| linux-hardened boot entry | pending | | Option 2 in systemd-boot. Default stays `linux` for `broadcom-wl` |
| LUKS2 pull-the-drive | n/a live | | install-time |
| TPM2 fail-to-passphrase | n/a live | | MBA Apple EFI: no Cicada TPM story |
| sbctl re-sign pacman hook | n/a until enrolled | | hook no-ops if sbctl not installed/enrolled |

Fail closed: VPN without config does not enable the kill switch. Kernel default on this ISO is `linux` so Broadcom Wi-Fi works; hardened is an explicit boot choice.
