#!/usr/bin/env bash
# Runs inside arch-chroot after pacstrap. Configures locale, initramfs, systemd-boot, user.
set -euo pipefail

HOST="$(cat /etc/hostname)"
# shellcheck disable=SC1091
source /etc/cicada/install.env

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc || true

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf

# systemd-boot: kernels live on the ESP mounted at /boot
if [[ -f /etc/mkinitcpio.conf ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block cicada-crypt filesystems fsck)/' \
    /etc/mkinitcpio.conf
fi
mkinitcpio -P

bootctl install --esp-path=/boot

mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf <<EOF
default cicada.conf
timeout 3
console-mode max
editor no
EOF

CMDLINE="cryptdevice=UUID=${CICADA_LUKS_UUID}:cicada root=UUID=${CICADA_ROOT_UUID} rw intel_iommu=on,igfx_off iommu.passthrough=0 init_on_alloc=1 init_on_free=1 ibt=on shstk=on"
if [[ -n "${CICADA_BTRFS_SUBVOL:-}" ]]; then
  CMDLINE="${CMDLINE} rootflags=subvol=${CICADA_BTRFS_SUBVOL}"
fi

ucode=""
[[ -f /boot/intel-ucode.img ]] && ucode="initrd /intel-ucode.img"
[[ -f /boot/amd-ucode.img ]] && ucode="${ucode}"$'\n'"initrd /amd-ucode.img"

cat > /boot/loader/entries/cicada.conf <<EOF
title Cicada.OS
linux /vmlinuz-linux
${ucode}
initrd /initramfs-linux.img
options ${CMDLINE}
EOF

if [[ -f /boot/vmlinuz-linux-hardened ]]; then
  cat > /boot/loader/entries/cicada-hardened.conf <<EOF
title Cicada.OS (linux-hardened)
linux /vmlinuz-linux-hardened
${ucode}
initrd /initramfs-linux-hardened.img
options ${CMDLINE} lockdown=confidentiality
EOF
fi

# User: no autologin. Empty live password must not follow onto disk.
id cicada >/dev/null 2>&1 || useradd -m -G wheel,video,audio,storage,rfkill,network,input,users -s /bin/bash cicada
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
if [[ -f /root/.cicada-user-pass ]]; then
  echo "cicada:$(cat /root/.cicada-user-pass)" | chpasswd
  shred -u /root/.cicada-user-pass 2>/dev/null || rm -f /root/.cicada-user-pass
fi
passwd -l root || true

if [[ -f /usr/lib/libhardened_malloc.so && ! -f /etc/cicada/hardened-malloc-disable ]]; then
  echo '/usr/lib/libhardened_malloc.so' > /etc/ld.so.preload
fi

if [[ -d /etc/skel ]]; then
  rsync -a /etc/skel/ /home/cicada/
  chown -R cicada:cicada /home/cicada
fi

systemctl enable NetworkManager.service
systemctl enable nftables.service
systemctl enable usbguard.service || true
systemctl enable apparmor.service || true
systemctl enable cicada-radios-off.service || true
systemctl enable cicada-locked-reboot.timer || true
systemctl mask sshd.service || true

# Installed system is not the live ISO — no getty autologin.
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf

echo "==> chroot done host=${HOST} luks=${CICADA_LUKS_UUID}"
