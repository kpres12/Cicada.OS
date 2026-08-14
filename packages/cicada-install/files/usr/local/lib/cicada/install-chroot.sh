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

CMDLINE="cryptdevice=UUID=${CICADA_LUKS_UUID}:cicada root=UUID=${CICADA_ROOT_UUID} rw quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 intel_iommu=on,igfx_off iommu.passthrough=0 init_on_alloc=1 init_on_free=1 ibt=on shstk=on"
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
# Installed: passworded sudo. Never keep live NOPASSWD.
rm -f /etc/sudoers.d/cicada-live
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
if [[ -f /root/.cicada-user-pass ]]; then
  echo "cicada:$(cat /root/.cicada-user-pass)" | chpasswd
  shred -u /root/.cicada-user-pass 2>/dev/null || rm -f /root/.cicada-user-pass
fi
passwd -l root || true

# Opt-in only — global preload crashes Helium (Tirimid browse). Enable later:
#   touch /etc/cicada/hardened-malloc-enable && echo '/usr/lib/libhardened_malloc.so' > /etc/ld.so.preload
if [[ -f /usr/lib/libhardened_malloc.so ]] \
   && [[ -f /etc/cicada/hardened-malloc-enable ]] \
   && [[ ! -f /etc/cicada/hardened-malloc-disable ]]; then
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
systemctl enable cicada-locked-reboot.timer || true
# The installed system needs firstboot too: it is what initialises the seal log
# and the device attestation key. Previously the unit lived only in the live
# overlay, so on a real install the binary shipped but nothing ever ran it.
systemctl enable cicada-firstboot.service || true
# Hardware AFU ceiling; exits 2 and stays inactive on boards with no watchdog.
systemctl enable cicada-watchdog.service || true
systemctl enable tor.service || true
systemctl enable cicada-tor-netns.service || true
# Authenticated time. Plaintext NTP lets an on-path attacker move the clock
# past certificate expiry, which turns TLS validation into a formality.
systemctl disable systemd-timesyncd.service 2>/dev/null || true
systemctl mask systemd-timesyncd.service 2>/dev/null || true
systemctl enable chronyd.service || true
# Guest agents are a host-to-guest control channel; never on by default.
for u in vboxservice vmtoolsd vmware-vmblock-fuse qemu-guest-agent ModemManager; do
  systemctl disable "${u}.service" 2>/dev/null || true
  systemctl mask "${u}.service" 2>/dev/null || true
done
systemctl enable cicada-memwipe.service || true

# ESP dir for LUKS fail counter (initramfs writes cicada/luks-fail.count).
mkdir -p /boot/cicada
echo "${CICADA_LUKS_MAX_FAIL:-20}" > /boot/cicada/max-fail 2>/dev/null || true
# Prefer value from defaults if present on the live stick being copied.
if [[ -f /etc/cicada/defaults.env ]]; then
  # shellcheck disable=SC1091
  . /etc/cicada/defaults.env
  echo "${CICADA_LUKS_MAX_FAIL:-20}" > /boot/cicada/max-fail
fi

# Launcher monopoly + channel pin on the installed root.
if [[ -x /usr/local/lib/cicada/hide-arch-desktops.sh ]]; then
  /usr/local/lib/cicada/hide-arch-desktops.sh || true
fi
if [[ -x /usr/local/lib/cicada/cicada-channel-enable.sh ]]; then
  /usr/local/lib/cicada/cicada-channel-enable.sh /etc/pacman.conf || true
fi

# Work UID is created on firstboot (create-locked). Marker for owner UI.
mkdir -p /etc/cicada
echo 'WORK_UID=pending' > /etc/cicada/work-uid.env

# Root of trust: use the strongest this machine actually has, but never enrol
# something that weakens the disk. TPM sealing WITHOUT a PIN makes a laptop
# unlock itself on power-on — worse than a passphrase — and enrolling a PIN
# needs a human at a keyboard, which we do not have inside pacstrap. So detect,
# report, and hand the user the one command; do not silently seal.
if [[ -c /dev/tpmrm0 || -c /dev/tpm0 ]]; then
  cat <<'TPMEOF'
==> TPM2 detected. This machine can do the strong path:

      cicada-tpm-enroll

    That seals the disk key to the TPM behind a PIN, and the TPM rate-limits
    PIN guessing in hardware — the property that makes a short PIN safe. Run it
    after first boot. It is NOT run automatically: enrolling without a PIN would
    make this disk unlock itself whenever it powers on.
TPMEOF
  if command -v sbctl >/dev/null 2>&1 && sbctl status 2>/dev/null | grep -qi 'setup mode.*enabled'; then
    echo "==> Firmware is in Setup Mode: cicada-sbctl-enroll will give you verified boot."
  fi
else
  echo "==> No TPM2: the passphrase is the sole root of trust on this machine."
  echo "    Nothing here can rate-limit guessing, which is why cicada-install"
  echo "    generates a high-entropy passphrase rather than accepting a short one."
  echo "    Consider a removable second factor: cicada-keyfile-enroll --and ..."
fi
systemctl mask sshd.service || true

# Brand: never leave Arch Linux / generic strings on an etched disk.
cat > /etc/os-release <<'EOF'
NAME="Cicada.OS"
PRETTY_NAME="Cicada.OS"
ID=cicada
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="1;33"
HOME_URL="https://github.com/kpresler12/Cicada.OS"
DOCUMENTATION_URL="https://github.com/kpresler12/Cicada.OS"
LOGO=cicada
CICADA_CODENAME=nimbus
CICADA_CHANNEL=stable
EOF
cat > /usr/lib/os-release <<'EOF'
NAME="Cicada.OS"
PRETTY_NAME="Cicada.OS"
ID=cicada
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="1;33"
HOME_URL="https://github.com/kpresler12/Cicada.OS"
DOCUMENTATION_URL="https://github.com/kpresler12/Cicada.OS"
LOGO=cicada
EOF
cat > /etc/issue <<'EOF'

      '-.       ,   ,       .-'
         \    _.-'"'-._    /
          \  (_).---.(_)  /
           '-/         \-'
             \__.---.__/
             / .'   '. \
         ,--(_;.-----.;_)--,
        /   |  \     /  |   \
       /   /;'-.'._.'.-';\   \
    ,-'   /, \~ \-=-/ ~/ ,\   '-,
         ; ;  |~ '.' ~|  ; ;
         |; '  \=====/  ; ;|
        /| ; ;_| === |_; ; |\
       / |  \_/;= = =;\_/  | \
     _/  | ; ;_ \===/ _; ; |  \_
    `    |  \_/ ;\=/; \_/  |    `
         | \_| ; ;|; ; |_/ |
         ;\_/ ; ;/ \; ; \_/;
         ;/, ; ; | | ; ; ,\;
          ; ; ; /   \ ; ; ;
          \; ; ;|   |; ; ;/
           \; ; /   \ ; ;/
            \_.'     '._/

                 C I C A D A . O S
\r (\l)

EOF
echo 'Cicada.OS' > /etc/issue.net

# Installed system is not the live ISO — no getty autologin, no live sudo.
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rm -f /etc/sudoers.d/cicada-live
# Drop Install/Etch icon from the etched desktop (live-only surface).
rm -f /home/cicada/Desktop/install.desktop \
      /home/cicada/Desktop/etch.desktop \
      /etc/skel/Desktop/install.desktop 2>/dev/null || true

echo "==> chroot done host=${HOST} luks=${CICADA_LUKS_UUID}"
