# Public release (beta)

Live USB stays the **try / QA** path. Installed disk is the **product**.

## What “public beta” means

| Surface | Status |
|---|---|
| Live ISO on USB | Supported for testing. Overlay is RAM. Do not enroll duress/TPM here. |
| `cicada-install` → LUKS disk | Supported daily path. Files, wallpaper, Work UID persist. |
| Signed hosted `cicada-stable` mirror | Not yet — pin + local repo after ISO build |
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
gh release create "vYYYY.MM.DD-beta" \
  --title "Cicada.OS YYYY.MM.DD (public beta)" \
  --notes-file docs/release-notes-beta.md \
  "$ISO" "${ISO}.sha256"
```

Site Download button already points at `releases/latest`.

## Before you hit publish

1. `bash tests/here.sh` green
2. Rebuild ISO (includes 2-entry boot menu)
3. Flash USB, smoke: Wi-Fi, Helium, Files, Settings wallpaper (on **install**)
4. Run `cicada-install` onto a spare disk once; confirm firstrun wizard (not on live)
5. Attach ISO + sha256 to the GitHub Release
6. Announce: live = beta demo, install = keep your files

## First-run (installed only)

`cicada-firstrun` (Hyprland exec-once, skips `/run/archiso`):

1. Welcome — installed vs live
2. Optional Work password
3. Optional duress enroll
4. TPM PIN or USB token (by hardware)
5. Point at Files / Appearance wallpaper

## Channel

Until a hosted signed repo exists, document: pin from `channel/CURRENT`; rebuild for updates. Do not tell beta users to `pacman -Syu` from raw Arch as the product story.
