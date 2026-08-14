# Cicada is its own OS

Arch is the warehouse. Cicada is the product. Graphene is still AOSP; people do not call it “AOSP + hardening” because the user cannot launch AOSP. Same rule here: **the user cannot launch Arch.**

## Claims (do not collapse them)

| Claim | When true |
|---|---|
| Trackers / school HTTPS filter / casual thief with disk **off** | Strong passphrase + Helium managed policy + LUKS. Mostly now. |
| LEO with **AFU** (on or just locked) | Never “can’t.” Shorten the window; HID-allow USBGuard; reboot timer. Still userspace. |
| Firmware / evil maid on Apple EFI Air | Never. Different laptop (Heads/PureBoot) is the boot story. |
| **Cicada is its own OS** | Launcher monopoly + default-deny scopes for boxed apps; Work-as-UID; channel-shaped updates. Kitty / Settings / Wi-Fi stay host-admin; Helium gets an outer bwrap without `--unshare-pid` (zygote) and still needs `--no-sandbox` inside. Identity, not uncrackability. |

## Product layers (ship order)

1. **Launcher monopoly** — dock, Waybar, Super+Space, desktop icons, MIME only start Cicada wrappers / `cicada-run <app-id>`. `cicada-wofi` sees `/usr/share/cicada/launchers` only. `hide-arch-desktops.sh` writes `Hidden=true` overrides for Arch `.desktop` files.
2. **Default-deny scopes** — unknown app-ids get `NETWORK=deny` `FILES=deny` (and cam/mic/usb/sensors deny) when launched through `cicada-run` + bwrap. System floors live under `/usr/share/cicada/scopes`; user scopes may only tighten. Helium / Tor Browser / Files / Doom / KeePassXC are boxed; Helium/Tor omit `--unshare-pid` so the zygote lives, and Helium still passes `--no-sandbox` for the inner Chromium namespace. Kitty / Settings / Wi-Fi / install / start are **host-admin** (no outer bwrap). System **Camera & microphone** kill is separate (`cicada-av-kill`).
3. **Work-as-UID** — install firstboot creates locked `cicada-work`. Settings → Profiles → Set Work password, then Login Work. Directory Burner only re-points `HOME` for `cicada-run` (not Work).
4. **Channel** — `cicada-update` upgrades packages listed in `[cicada-stable]` only. Hosted mirrors require a Cicada pubkey (`SigLevel=Required`); unsigned remote Servers are refused. Local `file://` repo may stay optional until the first signed build.

## Owner shell

Kitty stays an unsandboxed owner shell (like `adb`). It still goes through `cicada-run org.cicada.kitty` for identity. Settings / Wi-Fi / install are the same host-admin class. Helium / Files / Doom / Tor / KeePassXC run under bwrap with scopes (Helium without `--unshare-pid`). Do not treat the dock as a kernel sandbox. Flatpak apps from `cicada-pkg` get `--nofilesystem=home` overrides after install — they are not on the Cicada scopes sheet.
