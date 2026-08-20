# Cicada.OS 2026.08.19 — pre-alpha

**Pre-alpha.** Boots to a Hyprland desktop; most of the hardening is verified
structurally or against a real Linux kernel, and little of it has been exercised
on hardware end to end. Do not rely on this for anything that matters yet.

- **Site:** https://kpres12.github.io/Cicada.OS/
- **Install guide:** https://kpres12.github.io/Cicada.OS/install/
- **Threat model:** https://github.com/kpres12/Cicada.OS/blob/main/docs/THREAT_MODEL.md

## One file again

The image is **1.94 GiB**, under GitHub's 2 GiB per-asset cap, so it downloads as
a single ISO — no `.part-*` and nothing to reassemble before you can flash it.
It was 2.95 GiB. Three measured cuts:

| Cut | Saved | Why |
|---|---|---|
| `linux-hardened` off the **live** ISO | 645 MiB | Neither live boot entry could load it — both name `vmlinuz-linux`. It was a kernel, a 233 MiB initramfs and a second copy of both inside the embedded `efiboot.img`. Installed systems still get it. |
| `linux-firmware-nvidia` | 320 MiB | 110 MiB of it sat inside *every* initramfs. A laptop with an NVIDIA dGPU still boots and runs on its integrated GPU. |
| `linux-firmware-marvell` | 78 MiB | Enterprise NICs and embedded parts. |

Either is one command away: `sudo pacman -S linux-firmware-nvidia`. Firmware for
Intel, AMD, Atheros, Realtek, MediaTek, Broadcom, Radeon and Cirrus all stays.

## Installing

- **No network required.** The installer copies the system you are running
  instead of downloading 1.2 GiB, so it works offline, is faster, and gives you
  exactly the image that was tested. A laptop whose Wi-Fi does not work yet can
  now be installed. `--source network` restores the old behaviour.
- **Keyboard, timezone and language are asked for**, and the keymap is applied
  *before* the passphrase prompt. They used to be hardcoded to `us`/UTC/`en_US`.
  On this OS the keymap is a security setting: it decides which bytes your keys
  produce, and a mismatch between install time and boot time makes the disk
  unopenable by anybody, with no recovery.
- **Dual boot.** `cicada-install --partition /dev/sdXN --esp /dev/sdXM` installs
  into one partition, leaves the partition table alone and reuses the existing
  EFI partition without formatting it. It deliberately does **not** resize NTFS
  or APFS — use Disk Management or Disk Utility for that first.

## Security fixes

Four controls were reporting success while doing nothing:

- **Session duress was inert at the lock screen** — the situation it exists for.
  `pam_exec seteuid` gives the caller's effective uid, which is root under
  `sudo` but the desktop user under hyprlock, which is not setuid. It could not
  read the verifier, let alone erase a keyslot, and exited 0 — the same exit a
  wrong guess produces. A root handler now sits behind `cicada-duress.socket`,
  exercised as an unprivileged uid on a real kernel.
- **Granting an app the microphone also granted it the session bus** and the
  systemd user manager socket, because `cicada-run` bound the whole runtime
  directory for `MIC=allow`. Shipped scopes were unaffected.
- **The D-Bus filter failed open** under load, handing the app the real bus.
- **`cicada-auth` confirmations were bypassable** by calling the privileged
  helper directly through NOPASSWD sudo.

## Apps

`cicada-pkg` now offers 18 Flatpak applications under system-level permission
floors, including Thunderbird, Nuclear, Obsidian, OnlyOffice and Bitwarden.

## Verify before you boot

```bash
gpg --import cicada-stable.pub
gpg --fingerprint stable@cicada.os
# must equal: CAAC 3467 D0BB B357 231A  04A6 4755 854B FFDF 59F9
gpg --verify cicada-2026.08.19-x86_64.iso.sha256.asc cicada-2026.08.19-x86_64.iso.sha256
shasum -a 256 -c cicada-2026.08.19-x86_64.iso.sha256
```

Check that fingerprint against the site, not against this release: a key shipped
beside the thing it signs proves only that both came from the same place.
