# cicada-stable

Arch stays the engine. This directory is the **channel**: a tested package set, not a rewrite.

Users should never be told to “just add Arch mirrors and `pacman -Syu`.” Product updates go through **`cicada-update`**, which syncs and upgrades packages listed in `[cicada-stable]` only.

## Layout

| Piece | Role |
|---|---|
| Version lockfile (NEVR list) | Contract for a booted ISO pin |
| Helium tarball pin (`helium.lock`) | Official Helium Linux (not AUR) |
| Local `file:///var/cache/cicada/repo` | Embedded after ISO build |
| Hosted mirror | `/etc/cicada/channel-mirror.url` → `Server = https://…` |
| `SigLevel` | `Required` when pubkey is on disk; optional until first sign |
| Meta-package | `packages/cicada-desktop` — one unit for desk + greeter stack |

## Operator pipeline

1. Build ISO (`./scripts/build-iso-docker.sh`) — persists pacman cache → `out/channel-repo/`
2. `scripts/channel-sign.sh out/channel-repo` — signs db; exports pubkey
3. Rebuild ISO so assemble embeds `var/cache/cicada/repo` + pubkey
4. Firstboot / etch runs `cicada-channel-enable.sh` so `[cicada-stable]` is preferred before `[core]`
5. `scripts/channel-publish.sh` — upload signed repo as GitHub Release `channel-latest`
6. On machines:  
   `echo 'https://github.com/OWNER/REPO/releases/download/channel-latest' | sudo tee /etc/cicada/channel-mirror.url`  
   then `sudo cicada-update`

Private key: `channel/keys/gnupg/` (gitignored). Public: `channel/keys/cicada-stable.pub` and `/etc/pacman.d/cicada-stable-key.gpg` on the ISO.

## Snapshots

- [cicada-stable-2026.08.12.pkglist.txt](cicada-stable-2026.08.12.pkglist.txt)
- [helium.lock](helium.lock)
- [CURRENT](CURRENT)
