# cicada-stable

Arch stays the engine. This directory is the **channel**: a tested package set, not a rewrite.

## Product identity (step 4)

“Cicada is its own OS” needs a signed update path. Until then, a lockfile is the contract and Arch `extra` is still the warehouse.

| Now | Next |
|---|---|
| Version lockfile (NEVR list from a booted ISO) | Hosted pacman repo of the `.pkg.tar.zst` blobs |
| Helium tarball pin (`helium.lock` sha256) | GPG-signed `cicada-stable` mirror URL |
| Local `file:///var/cache/cicada/repo` after ISO build | Public Server=https://… |
| `scripts/channel-build-repo.sh` + `channel-sign.sh` | CI signs every promote |
| ISO `pacman.conf` prefers `[cicada-stable]` before `[core]` | Same |

`scripts/channel-verify.sh` checks the pins in this tree. A repo db appears under `out/channel-repo/` after an ISO build; the next assemble embeds it into the live image.

## Snapshots

- [cicada-stable-2026.08.12.pkglist.txt](cicada-stable-2026.08.12.pkglist.txt) — first ISO
- [helium.lock](helium.lock) — official Helium Linux tarball (not AUR)
- [CURRENT](CURRENT) — which snapshot is “stable”

## How to finish the signed channel

1. Build ISO (`./scripts/build-iso-docker.sh` or `iso/build.sh`) — persists pacman cache → `out/channel-repo/`
2. `scripts/channel-sign.sh out/channel-repo` — signs db; exports pubkey into the ISO overlay
3. Rebuild ISO so assemble embeds `var/cache/cicada/repo` + pubkey
4. Live/install firstboot runs `cicada-channel-enable.sh` so `[cicada-stable]` is preferred
5. Later: publish the same blobs; flip `Server=` from `file://` to https

Private key lives in `channel/keys/gnupg/` (gitignored). Public key: `channel/keys/cicada-stable.pub` and `/etc/pacman.d/cicada-stable-key.gpg` on the ISO.
