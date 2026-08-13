# Per-app permissions (Cicada Scopes)

## Plain English

On your phone, Instagram cannot see your files or use the network unless you toggle that on. The phone OS **is** the thing that starts Instagram, so it can sit in the middle and say no.

On a normal Linux laptop, clicking an app often just runs a program as *you*. There is no middleman. If Firefox can use Wi‑Fi, so can a random game you downloaded — same user, same keys to the house.

Cicada’s trick is to **stop launching apps directly**. The dock/launcher only starts a wrapper (`cicada-run`). That wrapper:

1. Knows which app you meant (an id like `org.cicada.helium`, not “whatever binary is named chrome”)
2. Checks your scopes sheet (network? files? camera?)
3. Starts the app in a box with only those things

If network is off, the app still opens — websites just fail like airplane mode. That is Graphene’s “network permission,” not a crash.

This is **not** as strong as Android. If malware breaks out of the box, it is still running as you. Phone apps are walled off from each other at a deeper level. We approximate the *feeling and the defaults*; we do not get Titan-grade isolation on a laptop.

The rest of this doc is the same idea with the actual Linux tools named.


We will not pretend Flatpak is that. We *will* ship a Graphene-*shaped* toggle UX and enforce it on everything the OS launches.

## Has anyone tried?

Yes. Nobody has finished it as a daily-driver OS.

| Project | What they actually did | Why it is not Graphene |
|---|---|---|
| **Flatpak + xdg-desktop-portal** | Bubblewrap sandbox + user prompts for files/camera/mic/USB | Mainstream. Undermined by apps shipping `--filesystem=home` and `--share=network`. Portals are the right *API*; Flathub culture is not a permission OS. |
| **Bubblejail** | GUI over bubblewrap: per-app home, toggles for network/audio/Wayland | Closest "toggle sheet" to Graphene. AUR, ~50 profiles, opt-in. Sidestep by running the binary unsandboxed. |
| **Firejail** | 1000+ profiles, SUID helper | Convenient, larger attack surface (SUID CVEs). Not a product permission model. |
| **NixPak** | Declarative bwrap wraps for Nix packages | Great if the whole OS is Nix. We are Arch-based. |
| **Spectrum OS** | VM-per-app (Qubes-lite) | Real isolation. Not a Hyprland daily driver yet. |
| **Qubes** | Xen compartments | Strongest isolation on PCs. Kills the MBA and the aesthetic. |
| **macOS TCC / Windows AppContainer** | OS-mediated permission prompts | Closest *UX*. Requires apps to call OS APIs; Linux apps mostly do not. |
| **secureblue** | Hardening + Flatpak recommendation | Does not add a new permission model. |

The honest read: **the plumbing exists (bwrap, netns, portals, USB portal). Cicada owns the launcher and default-deny scopes.** Remaining work is the signed channel and broader app catalog — not inventing a new kernel MAC.

## Cicada model — three layers

```
User taps "Helium"
        │
        ▼
 cicada-run (only launcher the dock/wofi uses)
        │
        ├─ profile netns / cgroup  (Work vs Burner)
        ├─ bubblewrap default-deny
        └─ Cicada Scopes file for that app-id
                NETWORK  allow | deny | vpn-only
                FILES    portal | deny | named-dir
                CAMERA   allow | deny
                MIC      allow | deny
                USB      deny  | portal
                SENSORS  deny  | allow
```

### Layer A — Identity (what Graphene gets for free)

Every launched app gets a **Cicada app-id** (`org.cicada.helium`, `org.keepassxc.KeePassXC`). Native packages are wrapped; Flatpaks already have an id. Unwrapped binaries are not in the launcher.

### Layer B — Enforcement (steal, don't invent)

- **Filesystem / camera / mic / USB:** xdg-desktop-portal (Hyprland + GTK backends). No `--filesystem=home`.
- **Network:** `bwrap --unshare-net` when scope is deny. Optional slirp4netns / netns + nftables when scope is vpn-only (ties to the kill switch).
- **D-Bus:** `xdg-dbus-proxy` (what Flatpak/Bubblejail already use).
- **Devices:** USBGuard + USB portal; no raw `/dev/bus/usb`.
- **Landlock** later, as a second floor under bwrap.

This is weaker than Android UIDs: a compromised app that escapes bwrap is still *your user*. Profiles (separate UIDs/homes) are the blast-radius layer above this.

### Layer C — UX (what we actually have to design)

Graphene's trick is the **settings page**, not the kernel. Cicada Scopes is that page:

- Super+I opens the MAGI scopes panel
- Per app: NETWORK / FILES / CAMERA / MIC / USB / SENSORS
- Deny looks like "network down", not a crash — wrappers return ENETUNREACH / empty portal
- Changing a scope restarts that sandbox only

v0 ships the panel (Settings → App permissions / Super+I), the launcher catalog, and enforcement on Helium, Files, and KeePassXC. `cicada-run` defaults are **deny/deny**. Known apps ship `.env` overrides. Dock / Wofi / MIME only start Cicada wrappers — see [docs/PRODUCT.md](PRODUCT.md). Kitty / Settings / Wi-Fi stay host-admin (identity via app-id, no bwrap).

## What we will not do

- Kernel-wide MAC that sandboxes every existing Arch package without a wrapper (SELinux on Fedora still doesn't give Graphene toggles)
- Claim Flatseal == Graphene
- VM-per-app on the MBA
