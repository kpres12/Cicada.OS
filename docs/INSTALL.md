# Install / Etch Cicada

Live USB is the demo. **Etch** writes LUKS2 + btrfs + systemd-boot to a disk you reboot into as the product.

## On the live USB

1. Boot Cicada. Click **Wi-Fi** (`pacstrap` needs network).
2. Plug the **install** disk (not the live stick).
3. Click **Etch Cicada** on the desktop (or dock / `cicada-etch`).
4. Pick the disk, set a LUKS passphrase, set the **cicada** login password.
5. Wait for pacstrap. Shut down, remove the USB, boot the etched disk.

CLI equivalent:

```bash
sudo cicada-install --list
sudo cicada-install --target /dev/sdX
# Framework-class NVMe:
sudo cicada-install --target /dev/nvme0n1 --internal
```

Apple internal SSDs are **always refused**. The live USB is refused.

## After reboot (real login)

1. Unlock **LUKS** with the disk passphrase.
2. **Login** as `cicada` with the password you chose (getty → Hyprland). No autologin.
3. **Firstrun** offers: Work profile password, power-on duress, lock-screen duress, TPM/USB token.

Root is locked; use `sudo` (password = your login password on installed systems).

## Later hardening

- TPM2: `sudo cicada-tpm-enroll`
- Firmware Setup Mode: `sudo cicada-sbctl-enroll` (Apple EFI exits 2)
- Duress: `sudo cicada-duress-enroll` and/or `--session`
- Backups to a **USB**: `CICADA_BACKUP_REPO=... cicada-backup init`
