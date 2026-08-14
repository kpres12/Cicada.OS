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

1. Build ISO (`./scripts/build-iso-docker.sh`) — the builder's pacman cache becomes `out/channel-repo/`
2. `scripts/channel-sign.sh out/channel-repo` — signs the db, writes the `.db.sig` / `.files.sig` short names pacman actually requests, exports the pubkey
3. `scripts/channel-publish.sh out/channel-repo channel-latest` — uploads the signed repo
4. `scripts/prepare-release.sh` — then the ISO, which already points at step 3

Order matters: the ISO ships `/etc/cicada/channel-mirror.url`, so publishing an image before the channel it names leaves `pacman -Sy` failing on every machine that installs it.

On the user's side there is nothing to configure. `cicada-channel-enable.sh` (run by firstboot and by `cicada-install`) imports the pubkey, **locally signs it** so pacman will trust the database, and writes `[cicada-stable]` ahead of `[core]`. It omits the `file://` server when no local database exists, so the empty `/var/cache/cicada/repo` on the ISO cannot break `pacman -Sy`.

Private key: `channel/keys/gnupg/` (gitignored, single copy — back it up). Public: `channel/keys/cicada-stable.pub` and `/etc/pacman.d/cicada-stable-key.gpg` on the ISO.

Packages are copied into the repo **with their `.sig` files**. `SigLevel = Required` is package-required as well as database-required: our key signs the database, each package keeps its Arch developer signature.

## Snapshots

- [cicada-stable-2026.08.12.pkglist.txt](cicada-stable-2026.08.12.pkglist.txt)
- [helium.lock](helium.lock)
- [CURRENT](CURRENT)
