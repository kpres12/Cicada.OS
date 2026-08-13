# Live USB that forgets (Tails-shaped)

Installed Cicada is a daily driver on LUKS. The **live ISO** is the amnesic mode.

## What is already true of archiso

The writable layer is a RAM overlay. Reboot without persistence = nothing from the session is on the stick. The squashfs on the USB is read-only.

That is **not** enough: secrets can still sit in RAM, the internal disk can still be mounted, and yanking the stick can hang instead of wiping.

## What Cicada adds

| Piece | Behavior |
|---|---|
| Default live entry | Overlay in RAM, squashfs still on USB. Fine for 8GB MBA. |
| **Amnesic** boot entry | `copytoram` + `cow_spacesize=2G` — ISO is copied into RAM; the stick can leave. Needs ~ISO size + 2G free RAM. |
| Internal disks | `cicada-amnesic` sets `UDISKS_IGNORE` on non-USB disks so the live session does not mount the Mac/Framework SSD. |
| Yank USB | udev on the boot UUID starts `cicada-panic` → `reboot --force`. Combined with `init_on_free=1`. |
| `cicada-panic` | Same path by hand (dock later / terminal). |

## Honesty

Unplug is **not** a cryptographic guarantee. There is no Tails `sdmem` pass over all physical RAM. The wipe is: drop caches, force reboot, kernel `init_on_free`. A cold-boot attack in the next few seconds is still in the threat model. Apple EFI MBA has no RAM encryption.

Do not save to the live USB. Do not enable persistence. For files you want to keep, `cicada-install` onto another stick/SSD or `cicada-backup` to a **different** USB.

## Boot menu

1. Cicada.OS live — daily-driver demo (USB stays in)
2. Cicada.OS live **(amnesic — copy to RAM)** — Tails-shaped
3. linux-hardened — extra
