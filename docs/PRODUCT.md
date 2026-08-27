# Cicada is its own OS

**Base OS: Arch Linux** (official repos — kernel, pacman, systemd). Cicada is the product layer on top.
It is **not** GrapheneOS, not AOSP, and not a phone OS. Graphene’s permission UX is an inspiration;
the enforcement here is Linux (`cicada-run` + bwrap + policy files), which is weaker than Android UIDs.

People do not call Graphene “AOSP + hardening” because the user cannot casually launch stock AOSP.
Same product rule here: the dock should not hand you raw Arch launchers — only Cicada wrappers.
Kitty remains an intentional owner-shell escape.

## Threats vs evidence (do not collapse them)

| Threat | What we ship | What we do not claim |
|---|---|---|
| Trackers / school HTTPS filter / cold stolen disk | Helium managed policy + LUKS2 (installed) | Graphene attestation / “uncrackable” |
| Seized while on or just locked (AFU) | Lock reboot timer, USB authorize gate, optional duress | Cellebrite-matrix “no access” |
| Evil maid on Apple EFI Air | Nothing that survives that class | Verified boot (needs Heads/PureBoot hardware) |
| “Just Arch with a theme?” | Launcher monopoly, scopes, Work UID, `cicada-update` | Android UID isolation or Qubes |

## Product layers (ship order)

1. **Launcher monopoly** — dock, Waybar, Super+Space, desktop icons, MIME only start Cicada wrappers / `cicada-run <app-id>`. `cicada-wofi` sees `/usr/share/cicada/launchers` only. `hide-arch-desktops.sh` writes `Hidden=true` overrides for Arch `.desktop` files.
2. **Default-deny scopes** — unknown app-ids get `NETWORK=deny` `FILES=deny` (and cam/mic/usb/sensors deny) when launched through `cicada-run` + bwrap. System floors live under `/usr/share/cicada/scopes`; user scopes may only tighten. Helium / Tor Browser / Files / Doom / KeePassXC are boxed; Helium/Tor omit `--unshare-pid` so the zygote lives, and Helium still passes `--no-sandbox` for the inner Chromium namespace. Kitty / Settings / Wi-Fi / install / start are **host-admin** (no outer bwrap). System **Camera & microphone** kill is separate (`cicada-av-kill`).
3. **Work-as-UID** — install firstboot creates locked `cicada-work`. Settings → Profiles → Set Work password, then Login Work. Directory Burner only re-points `HOME` for `cicada-run` (not Work).
4. **Channel** — `cicada-update` upgrades packages listed in `[cicada-stable]` only. Hosted mirrors require a Cicada pubkey (`SigLevel=Required`); unsigned remote Servers are refused. Local `file://` repo may stay optional until the first signed build.

## Owner shell

Kitty stays an unsandboxed owner shell (like `adb`). It still goes through `cicada-run org.cicada.kitty` for identity. Settings / Wi-Fi / install are the same host-admin class. Helium / Files / Doom / Tor / KeePassXC run under bwrap with scopes (Helium without `--unshare-pid`). Do not treat the dock as a kernel sandbox. Flatpak apps from `cicada-pkg` get `--nofilesystem=home` overrides after install — they are not on the Cicada scopes sheet.
