# Cicada.OS 2026.08.20 — pre-alpha

**Pre-alpha.** Same honesty as 2026.08.19: boots to a Hyprland desktop; do not
rely on this for anything that matters yet.

- **Site:** https://kpres12.github.io/Cicada.OS/
- **Install:** https://kpres12.github.io/Cicada.OS/install/
- **Base OS:** Arch Linux (official repos). Not GrapheneOS / not AOSP.

## What’s in this cut

- **1.90 GiB single-file ISO** (under GitHub’s 2 GiB asset cap) — signed
  `.sha256` + `.sha256.asc` + `cicada-stable.pub`.
- **Hosted update channel** at `channel-latest` + `channel-latest-2` (GitHub’s
  1000-asset cap forces a split; both roots are in `/etc/cicada/channel-mirror.url`).
  Database signed with the Cicada key; packages keep Arch `.sig` files.
  Sixty epoch’d packages (`ffmpeg`, `flatpak`, `fontconfig`, …) would have 404’d
  mid-upgrade: GitHub rewrites `:` to `.` in asset filenames without failing the
  upload, so the signed database named files the mirror did not serve. The
  database now records the served name; the epoch still reaches pacman through
  `%VERSION%`. `channel-verify-release.sh` gates publication on this.
- Product-layer Flatpak floors and honesty copy (Arch base, threats vs evidence).

Build id (tree when the ISO was assembled): commit `751b24b` (2026-08-20).
Site/docs honesty landing after that is on `main` and does not change the ISO bytes.

One cosmetic wart in the shipped image: `cicada-update` and Settings report the
channel pin as `cicada-stable-2026.08.12`, because `channel/CURRENT` still named
the older snapshot when the ISO was assembled. The mirror it syncs from is the
2026.08.20 set either way — the label is display-only and nothing resolves
against it. The pin is corrected in-tree and will read correctly in the next
image.

## Verify before you boot

```bash
gpg --import cicada-stable.pub
gpg --fingerprint stable@cicada.os
# must equal: CAAC 3467 D0BB B357 231A  04A6 4755 854B FFDF 59F9
gpg --verify cicada-2026.08.20-x86_64.iso.sha256.asc cicada-2026.08.20-x86_64.iso.sha256
shasum -a 256 -c cicada-2026.08.20-x86_64.iso.sha256
```

Check that fingerprint against the [download page](https://kpres12.github.io/Cicada.OS/download/),
not only against this release.

## Still needs a human on hardware

Wi‑Fi associate on the Intel MBA, install onto a spare disk, lock/USB AFU path —
see `docs/HARDWARE.md` and `docs/test-results.md`.
