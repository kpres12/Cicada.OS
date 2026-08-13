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

1. External USB SSD — leave internal macOS alone
2. Flash ISO to a USB stick
3. MBA: hold **Option (⌥)** → EFI Cicada
4. Live session autologins `cicada` and starts Hyprland (empty password)
5. Install with `archinstall` onto the **external** disk, LUKS on

Radios start **soft-blocked**. Unblock: `Super+Shift+R` or `cicada-radios-toggle`.

## Upstream in this repo

- `vendor/archiso` — official ISO tooling / releng profile
- `vendor/Hyprland` — compositor source (ISO still uses Arch's `hyprland` package)
