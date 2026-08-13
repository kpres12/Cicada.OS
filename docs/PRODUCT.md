# Cicada is its own OS

Arch is the warehouse. Cicada is the product. Graphene is still AOSP; people do not call it “AOSP + hardening” because the user cannot launch AOSP. Same rule here: **the user cannot launch Arch.**

## Claims (do not collapse them)

| Claim | When true |
|---|---|
| Trackers / school HTTPS filter / casual thief with disk **off** | Strong passphrase + Helium managed policy + LUKS. Mostly now. |
| LEO with **AFU** (on or just locked) | Never “can’t.” Shorten the window; HID-allow USBGuard; reboot timer. Still userspace. |
| Firmware / evil maid on Apple EFI Air | Never. Different laptop (Heads/PureBoot) is the boot story. |
| **Cicada is its own OS** | No unsandboxed path from dock / Wofi / MIME; scopes default-deny; Work-as-UID; channel signed. Identity, not uncrackability. |

## Product layers (ship order)

1. **Launcher monopoly** — dock, Waybar, Super+Space, desktop icons, MIME only start Cicada wrappers / `cicada-run <app-id>`. `cicada-wofi` sees `/usr/share/cicada/launchers` only. Arch `kitty` / `pcmanfm-qt` desktops are `Hidden=true`.
2. **Default-deny scopes** — unknown app-ids get `NETWORK=deny` `FILES=deny`. Helium / Files / KeePass ship explicit `.env` files. Settings → App permissions opens MAGI-02.
3. **Work-as-UID** — `cicada-profile create work --user` makes `cicada-work`. Same LUKS, different uid. Settings → Profiles. Directory Burner only re-points `HOME` for `cicada-run`.
4. **Signed channel** — `channel/` pin today; signed pacman repo next (`channel/README.md`). Until blobs are signed, `pacman -Syu` can still float Arch `extra`.

## Owner shell

Kitty stays an unsandboxed owner shell (like `adb`). It still goes through `cicada-run org.cicada.kitty` for identity. Settings / Wi-Fi / install are the same class: host D-Bus, no bwrap.
