# Building Cicada.OS

## Hosts

| Machine | Role |
|---|---|
| MacBook Pro M2 (this repo) | Develop configs, vendor trees, **cross-build** the Intel ISO |
| Intel MacBook Air 2015–2017 | Boot/install target (`linux/amd64` only) |

The ISO is **x86_64**. Docker on Apple Silicon must emulate `linux/amd64`. Enable Docker Desktop → Settings → General → **Use Rosetta for x86/amd64 emulation**.

## Build the ISO (M2 Mac)

```bash
./scripts/build-iso-docker.sh
# artifact: out/cicada-YYYY.MM.DD-x86_64.iso
```

Daily-driver extras (Chromium/Firefox):

```bash
CICADA_FULL=1 ./scripts/build-iso-docker.sh
```

The work directory lives in a Docker volume (`cicada-iso-work`), not a macOS bind-mount. pacstrap/chroot need a real Linux filesystem.

First run is slow: it pulls Arch packages under x86_64 emulation.

## ISO size

The image has to stay under **2 GiB**, GitHub's per-asset limit. Above it the
release ships as `.part-00`/`.part-01` and reassembling them with `cat` becomes
step one of every install — before the user can even flash. `tests/iso-size.sh`
checks a built image and warns while there is still headroom to act on:

```bash
tests/iso-size.sh                 # newest out/*.iso
tests/iso-size.sh path/to.iso
```

`scripts/prepare-release.sh` runs it automatically.

Things already tried, so they are not re-attempted:

- **Compression is maxed.** `mksquashfs` refuses blocks above 1 MiB and the xz
  dictionary cannot exceed the block size, so archiso's `-b 1M -Xdict-size 1M`
  is the ceiling, not a cautious default. Space must come out of content.
- **Installed size is a bad proxy.** `ttf-jetbrains-mono-nerd` is 228 MB
  installed and costs ~11 MiB on the image. Judge by the package's compressed
  size, which is roughly what lands in the squashfs.
- **The kernel and initramfs are written twice** — once to ISO 9660, once into
  the embedded `efiboot.img`, because systemd-boot can only read the ESP it was
  launched from. So every MiB removed from the initramfs saves two.

### CICADA_SLIM_INITRAMFS

```bash
CICADA_SLIM_INITRAMFS=1 ./scripts/build-iso-docker.sh
```

Drops the `kms` hook from the live initramfs. Measured on the 2026.08.19 image
that hook is 47.9 MiB — 36.0 MiB of GPU firmware (amdgpu alone is 28) and
11.9 MiB of DRM modules — and it is paid twice, so this is worth **~96 MiB**.

Nothing storage-related is affected: there is no storage or USB firmware in the
initramfs at all, and the block/filesystem modules come from other hooks.

**It is off by default because it needs a boot test, and that needs hardware.**
The cost is no native modesetting until the real root is mounted. On UEFI there
is always an EFI framebuffer console, so the screen should still work — the
driver simply arrives a second later. "Should" is why this is opt-in.

To promote it to the default:

1. Build with the flag and flash it.
2. Boot on the target machine — the Intel Air is the one that matters, and an
   AMD machine too if you have one, since amdgpu is most of what is removed.
3. Confirm: the boot console appears (any resolution), the greeter comes up, and
   `cicada-verify` passes. A black screen between the boot menu and the greeter
   is the failure this is guarding against.
4. If it boots, set the default in `iso/assemble-profile.sh` and move it onto
   the verified list in the README.

## Native Arch

```bash
sudo pacman -S --needed archiso
./iso/build.sh
```

## Flash + MBA

See [docs/USER.md](USER.md) — that is the first-boot sheet (also Super+/ on the live desktop).

1. Flash the ISO to JACKSPARROW (`diskutil list` — confirm 250 GB). macOS will say unreadable: **Eject**, not Initialize.
2. Air: hold **Option (⌥)** → Cicada.
3. Live autologin `cicada`, empty password. Radios blocked until you click Wi‑Fi.
4. Install: `sudo cicada-install --target /dev/sdX` (not `archinstall`). Apple internal disks are refused.

## Upstream in this repo

- `vendor/archiso` — official ISO tooling / releng profile
- `vendor/Hyprland` — compositor source (ISO still uses Arch's `hyprland` package)
