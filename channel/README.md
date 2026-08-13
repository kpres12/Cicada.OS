# cicada-stable

Arch stays the engine. This directory is the **channel**: a tested package set, not a rewrite.

## Product identity (step 4)

“Cicada is its own OS” needs a signed update path. Until then, a lockfile is the contract and Arch `extra` is still the warehouse.

| Now | Next (signed channel) |
|---|---|
| Version lockfile (NEVR list from a booted ISO) | Hosted pacman repo of the `.pkg.tar.zst` blobs |
| Helium tarball pin (`helium.lock` sha256) | GPG-signed `cicada-stable` mirror |
| Policy: daily drivers consume a pin, not raw `extra` | ISO `pacman.conf` prefers `[cicada-stable]` before `[extra]` |

`scripts/channel-verify.sh` checks the pins in this tree. It does not prove a rebuild matches until the blob repo exists.

## Snapshots

- [cicada-stable-2026.08.12.pkglist.txt](cicada-stable-2026.08.12.pkglist.txt) — first ISO
- [helium.lock](helium.lock) — official Helium Linux tarball (not AUR)
- [CURRENT](CURRENT) — which snapshot is “stable”

## How to finish the signed channel

1. Persist Docker’s `/var/cache/pacman/pkg` at ISO build time
2. `repo-add` those packages into `channel/repo/`
3. Sign the db with a Cicada release key; publish the pubkey on the ISO
4. Point live + installed `pacman.conf` at `[cicada-stable]` before `[extra]`
5. Only then does an MBA `pacman -Syu` stay on the pin
