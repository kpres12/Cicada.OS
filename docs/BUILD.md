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
