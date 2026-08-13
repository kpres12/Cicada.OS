# cicada-stable

Arch stays the engine. This directory is the **channel**: a tested package set, not a rewrite.

## Why this waited until tonight

A freeze with no successful ISO is a wishlist. We now have one: `out/cicada-2026.08.12-x86_64.iso`. The 654 packages that landed in that image are the first pin.

## What’s here vs what’s not

| Now | Not yet |
|---|---|
| Version lockfile (NEVR list from a booted-build ISO) | Hosted pacman repo of the `.pkg.tar.zst` blobs |
| A named snapshot we can rebuild against | GPG-signed `cicada-stable` mirror |
| Policy: daily drivers consume a pin, not raw `extra` | CI that promotes `extra` → stable after smoke boot |

Without the blobs, `pacman -S hyprland` still hits Arch `extra` and can float. The lockfile is the contract; the repo is the warehouse.

## Snapshots

- [cicada-stable-2026.08.12.pkglist.txt](cicada-stable-2026.08.12.pkglist.txt) — first ISO (`hyprland 0.56.2-1`, `linux 7.1.8.arch1-3`, …)
- [CURRENT](CURRENT) — which snapshot is “stable”

## Next (when we want rebuilds to match)

1. Persist Docker’s `/var/cache/pacman/pkg` in a volume at ISO build time
2. `repo-add` those packages into `channel/repo/`
3. Point the ISO `pacman.conf` at `[cicada-stable]` before `[extra]`
4. Only then does an MBA `pacman -Syu` stay on the pin
