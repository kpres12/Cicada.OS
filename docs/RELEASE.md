# Public release (beta)

Live USB stays the **try / QA** path. Installed disk is the **product**.

## What “public beta” means

| Surface | Status |
|---|---|
| Live ISO on USB | Supported for testing. Overlay is RAM. Do not enroll duress/TPM here. |
| `cicada-install` → LUKS disk | Supported daily path. Files, wallpaper, Work UID persist. |
| Signed hosted `cicada-stable` mirror | Live — `channel-latest` release; ISOs point at it out of the box |
| Graphene-class firmware claims | Never on Apple EFI Air |

## Cut a GitHub Release

From a machine that just built the ISO:

```bash
./scripts/prepare-release.sh
# prints version, sha256, and a gh release create command
```

Or manually:

```bash
ISO=out/cicada-YYYY.MM.DD-x86_64.iso
shasum -a 256 "$ISO" | tee "${ISO}.sha256"
GNUPGHOME=channel/keys/gnupg gpg --armor --detach-sign \
  --default-key stable@cicada.os "${ISO}.sha256"
GNUPGHOME=channel/keys/gnupg gpg --armor --export stable@cicada.os > cicada-stable.pub
gh release create "vYYYY.MM.DD-beta" \
  --title "Cicada.OS YYYY.MM.DD (public beta)" \
  --notes-file docs/release-notes-beta.md \
  "$ISO" "${ISO}.sha256" "${ISO}.sha256.asc" cicada-stable.pub
```

**Never publish unsigned.** A sha256 next to the ISO authenticates nothing:
whoever can replace the image can replace the hash beside it. The signature is
the only thing that makes the download verifiable, which is why
`prepare-release.sh` refuses to proceed without a signing key unless you set
`CICADA_ALLOW_UNSIGNED=1`. It signs the `.sha256` rather than the 3 GiB image —
SHA-256 already binds that file to the exact bytes, and downloaders reassemble
from parts anyway.

The verifying key must not be only the copy inside the ISO: that copy is
authenticated by the very thing it is supposed to authenticate. Publish
`cicada-stable.pub` as a release asset **and** put its fingerprint on the site,
so a downloader can cross-check the two.

Site Download button already points at `releases/latest`.

## Before you hit publish

1. `bash tests/here.sh` green
2. Rebuild ISO (includes 2-entry boot menu)
3. Flash USB, smoke: Wi-Fi, Helium, Files, Settings wallpaper (on **install**)
4. Run `cicada-install` onto a spare disk once; confirm firstrun wizard (not on live)
5. Attach ISO + sha256 + **signature + pubkey** to the GitHub Release
   (`prepare-release.sh` verifies the signature in a throwaway keyring first —
   signing then verifying with the secret key still present proves only that gpg ran)
6. Announce: live = beta demo, install = keep your files

## First-run (installed only)

`cicada-firstrun` (Hyprland exec-once, skips `/run/archiso`):

1. Welcome — etched install vs live
2. Optional Work password (`cicada-work`)
3. Optional LUKS duress (power-on wipe)
4. Optional session duress (hyprlock / sudo wipe)
5. TPM PIN or USB token (by hardware)
6. Point at Files / Appearance wallpaper

## Etch (install)

Live desktop: **Etch Cicada** → `cicada-etch` (GUI over `cicada-install`).
Live has passwordless sudo for etch only; installed disks strip that and require the login password for `sudo`.

## Channel

Every release ships two things: the **ISO** (tagged `vYYYY.MM.DD-beta`) and the **channel** (`channel-latest`, force-updated in place). The ISO carries `/etc/cicada/channel-mirror.url` pointing at the channel release, so an installed machine updates with `cicada-update` — Settings → Security → Check updates. Nothing polls; the user asks.

Cut them in this order, and do not skip it:

```bash
./scripts/build-iso-docker.sh          # also writes out/channel-repo from the pkg cache
./scripts/channel-sign.sh out/channel-repo
./scripts/channel-publish.sh out/channel-repo channel-latest   # channel first
./scripts/prepare-release.sh           # then the ISO that points at it
```

**Channel before ISO.** An image whose mirror URL resolves to a release that does not exist yet fails `pacman -Sy`, and `cicada-update` dies with a network error instead of saying anything useful.

What the channel is: the tested Arch snapshot the ISO was built from (~1.8 GiB, ~870 packages). Database signed with the Cicada key; packages keep their Arch developer signatures — that combination is what satisfies `SigLevel = Required` on the user's machine. It is **not** embedded in the ISO (that would add ~2 GiB to a 3 GiB image for no gain, since updating needs the network anyway); pass `CICADA_EMBED_CHANNEL=1` to `assemble-profile.sh` for a genuinely offline build.

Product-layer changes — the shell, dock, settings, pattern bay — ship as a **new ISO**, not through the channel, because the ISO lays those files down as a tree rather than as pacman-owned packages. The channel carries the Arch layer: kernel, openssl, browser runtime.

Do not tell beta users to `pacman -Syu` from raw Arch as the product story.

### Signing key

`channel/keys/gnupg/` is gitignored and is the only copy. Lose it and no existing ISO will ever trust a new channel again — every machine would report the mirror as tampered. Back it up off this laptop. `channel-sign.sh` refuses to mint a replacement unless `CICADA_CHANNEL_KEYGEN=1` is set explicitly.
