# Install Cicada

Live USB is the demo. This writes LUKS2 + btrfs + systemd-boot to a disk you can reboot into.

1. Boot the Cicada ISO. Click **Wi-Fi** (`pacstrap` needs network).
2. Plug the **install** disk (not the live stick).
3. `sudo cicada-install --list`
4. External SSD: `sudo cicada-install --target /dev/sdX`
5. Framework-class internal NVMe: `sudo cicada-install --target /dev/nvme0n1 --internal`

Apple internal SSDs (`APPLE SSD` / MacBook NVMe) are **always refused**. The live USB is refused.

You will set a LUKS passphrase and a `cicada` user password. Root is locked; use `sudo`. There is **no autologin** on the installed system.

After reboot:

- Machines with TPM2: `sudo cicada-tpm-enroll` (passphrase slot is kept; PCR 0,1,2,3,7).
- Firmware Setup Mode: `sudo cicada-sbctl-enroll` (Apple EFI will exit 2).
- Pin identity: `cicada-attest` then store `device.pub` on a Graphene Pixel. See [ATTEST.md](ATTEST.md).
- Backups to a **USB**, not this disk: `CICADA_BACKUP_REPO=... cicada-backup init` then `backup` / `restore`.

Duress: after install, `sudo cicada-duress-enroll`. Wrong PIN and duress both wait ~12s and print the same error; duress wipes keyslots and poweroffs.
