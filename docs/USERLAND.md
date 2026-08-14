# Own userland (without leaving Arch)

Cicada does **not** rebase to NixOS / Atomic / immutable Fedora. Arch stays the engine (see `.cursor/rules`). “Own userland” means **we own what the user sees and updates**, not that we fork glibc.

## What we own

| Surface | Cicada control |
|---|---|
| Identity | `PRETTY_NAME=Cicada.OS`, ASCII issue, boot titles, greeter greeting |
| Session | `cicada-login` → preferred session (`cicada-session` default; optional Sway/niri) |
| Login | greetd + tuigreet on etched installs (live stays autologin demo) |
| Apps | Helium pin, dock catalog, `cicada-run` scopes, `cicada-pkg` / Flatpak allowlist |
| Product unit | Meta-package `cicada-desktop` (desk + greeter + portal stack) |
| Updates | `cicada-update` upgrades **only** `[cicada-stable]` — not raw Arch rolling |
| Kernel choice | Etched default = `linux-hardened` + lockdown; `linux` = Wi‑Fi/Broadcom fallback |
| Disk unlock | `cicada-crypt` (duress + attempt cap); TPM PIN via `cicada-tpm-enroll` with passphrase fallback |
| Verified boot | `cicada-sbctl-enroll` + pacman re-sign hook (Setup Mode; not Apple EFI) |
| Allocator | `cicada-malloc` opt-in (default off — Helium) |
| Modules | `cicada-blacklist.conf` (DMA/exotic FS/test drivers) |
| Install | `cicada-etch` / `cicada-install` |

## Channel (hosted signed)

1. Build ISO → `out/channel-repo/` via `scripts/channel-build-repo.sh`
2. Sign → `scripts/channel-sign.sh out/channel-repo`
3. Publish → `scripts/channel-publish.sh` (GitHub Release tag `channel-latest`)
4. On machine: put the release download root in `/etc/cicada/channel-mirror.url`, then `cicada-update`

Pubkey: `channel/keys/cicada-stable.pub` → `/etc/pacman.d/cicada-stable-key.gpg` on ISO. With the key present, `SigLevel = Required`.

## Optional sessions

Settings → Appearance → Desktop session:

- **Cicada (default)** — product desk (Hyprland under the hood)
- **Sway** / **niri** — install on demand; greeter still shows Cicada-branded `.desktop` entries

## What we deliberately do not own

- Kernel tree, pacman, systemd (upstream Arch).
- Custom signed kernel / forced module signing fork.
- Replacing the default compositor unless something is clearly more secure *and* more daily-driveable on MBA-class hardware.
