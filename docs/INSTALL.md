# Install Cicada (external SSD only)

Live USB is the demo. This is the path to a disk you can reboot into.

1. Boot the Cicada ISO on the Intel Air (Option).
2. Click **Wi-Fi** and get an address (`pacstrap` needs network).
3. Plug the **install** SSD (not JACKSPARROW if that’s the live stick).
4. `sudo cicada-install --list` then `sudo cicada-install --target /dev/sdX`

The installer **refuses** `/dev/nvme*` and `APPLE SSD` (internal Mac disk). It **refuses** the live USB.

v0 stops before bootloader install on purpose. Finish with `arch-chroot /mnt` and `bootctl install` after you confirm LUKS UUID.

Duress slot: `cicada-duress-enroll` exits 1 until the unlock path is timing-safe.
