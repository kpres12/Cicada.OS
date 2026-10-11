# Own userland (without leaving Arch)

Cicada does **not** rebase to NixOS / Atomic / immutable Fedora. Arch stays the engine (see `.cursor/rules`). “Own userland” means **we own what the user sees and updates**, not that we fork glibc.

## What we own

| Surface | Cicada control |
|---|---|
| Identity | `PRETTY_NAME=Cicada.OS`, ASCII issue, boot titles, greeter greeting |
| Session | `cicada-login` → preferred session (`cicada-session` default; optional Sway/niri) |
| Login | greetd + tuigreet on etched installs (live stays autologin demo) |
| Apps | Helium pin (`cicada-helium` + `channel/helium.lock`), dock catalog, `cicada-run` scopes, `cicada-pkg` / Flatpak allowlist |
| Product unit | Pacman packages on `[cicada-stable]`: `cicada-shell`, `cicada-run`, `cicada-defaults`, `cicada-profiles`, `cicada-install`, `cicada-malloc`, `cicada-helium`, meta `cicada-desktop` |
| Desk pin | `channel/hyprland.lock` — tested Hyprland/portal/dock NEVRs; `scripts/channel-pin-hyprland.sh` |
| AppArmor | Cicada profiles under `/etc/apparmor.d/cicada-*` (installed systems; LSM via `lsm=`) |
| Updates | `cicada-update` upgrades **only** `[cicada-stable]` — not raw Arch rolling. Product packages ship Cicada `.sig`s; Arch packages keep upstream sigs |
| Kernel choice | Etched default = `linux-hardened` + lockdown; `linux` = Wi‑Fi/Broadcom fallback |
| Disk unlock | `cicada-crypt` (duress + attempt cap); TPM PIN via `cicada-tpm-enroll` with passphrase fallback |
| Verified boot | `cicada-sbctl-enroll` + pacman re-sign hook (Setup Mode; not Apple EFI) |
| Allocator | `cicada-malloc` package + `cicada-malloc` CLI (default off — Helium) |
| Modules | `cicada-blacklist.conf` (DMA/exotic FS/test drivers) |
| Install | `cicada-etch` / `cicada-install` |

## Channel (hosted signed)

1. Build ISO → `out/channel-repo/` via `scripts/channel-build-repo.sh` (includes `channel-build-meta.sh` for all `cicada-*` product packages)
2. Sign → `scripts/channel-sign.sh out/channel-repo` (database + Cicada-signed product packages)
3. Publish → `scripts/channel-publish.sh` (GitHub Release tag `channel-latest` + overflow `channel-latest-2`)
4. Product-only refresh (no full Arch republish) → `CICADA_BUILD_HELIUM=1` + `scripts/channel-build-meta.sh` then `scripts/channel-publish-product.sh`
5. Helium cadence check → `scripts/check-helium-upstream.sh` (Class A, 72h — `docs/SECURITY_UPDATES.md`)
6. On machine: put the release download root(s) in `/etc/cicada/channel-mirror.url`, then `cicada-update`

Pubkey: `channel/keys/cicada-stable.pub` → `/etc/pacman.d/cicada-stable-key.gpg` on ISO. With the key present, `SigLevel = Required`.

## ISO: pacman-owned product trees

On the Arch/Docker builder, `iso/assemble-profile.sh` runs `scripts/iso-stage-product-pkgs.sh`, adds a local `[cicada-product]` repo, and pacstraps `cicada-*` so **pacman owns** the desk files. Helium is still embedded with `install-helium.sh` for first-boot fail-fast; upgrades use `cicada-helium` from the channel.

On macOS assemble (no `makepkg`), the same trees are rsynced — same bytes, untracked until `cicada-update` installs the packages.

## Hyprland pin (when Arch breaks the desk)

1. Boot a known-good image; run `scripts/channel-pin-hyprland.sh` to refresh `channel/hyprland.lock`
2. `scripts/channel-pin-hyprland.sh --check` fails CI/drift when the snapshot moved without a re-pin
3. If Arch mid-channel breaks tiling/dock: rebuild those packages from upstream tags into `cicada-stable` (same signing path as other product packages) — do **not** send users to raw rolling

## Optional sessions

Settings → Appearance → Desktop session:

- **Cicada (default)** — product desk (Hyprland under the hood)
- **Sway** / **niri** — install on demand; greeter still shows Cicada-branded `.desktop` entries

## What we deliberately do not own

- Kernel tree, pacman, systemd, glibc, mesa, firmware (upstream Arch).
- Custom signed kernel / forced module signing fork.
- Replacing the default compositor unless something is clearly more secure *and* more daily-driveable on MBA-class hardware.
