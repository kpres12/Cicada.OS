#!/usr/bin/env bash
# Runs inside arch-chroot after pacstrap. Configures locale, initramfs, systemd-boot, user.
set -euo pipefail

HOST="$(cat /etc/hostname)"
# shellcheck disable=SC1091
source /etc/cicada/install.env

# Region comes from install.env, which cicada-install wrote after asking. These
# three were hardcoded to UTC / en_US.UTF-8 / us and never asked about, which
# meant every non-US owner typed their LUKS passphrase on a layout that did not
# match their keycaps, at install and at every unlock after it. The fallbacks
# below keep older install.env files working.
TZ_="${CICADA_TIMEZONE:-UTC}"
KEYMAP_="${CICADA_KEYMAP:-us}"
LOCALE_="${CICADA_LOCALE:-en_US.UTF-8}"

if [[ -f "/usr/share/zoneinfo/${TZ_}" ]]; then
  ln -sf "/usr/share/zoneinfo/${TZ_}" /etc/localtime
else
  echo "==> WARNING: unknown timezone ${TZ_}; falling back to UTC" >&2
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  TZ_=UTC
fi
hwclock --systohc || true

# Generate the chosen locale plus en_US.UTF-8. Keeping the C-adjacent fallback
# means a bad locale choice degrades to readable English rather than to a system
# whose every program warns about an unusable LC_ALL.
sed -i "s/^#\(${LOCALE_//./\.}\)/\1/" /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE_}" > /etc/locale.conf

# vconsole.conf is what the initramfs keymap hook reads, so this line is what
# makes the LUKS prompt agree with the keyboard the passphrase was chosen on.
echo "KEYMAP=${KEYMAP_}" > /etc/vconsole.conf

# systemd-boot: kernels live on the ESP mounted at /boot
if [[ -f /etc/mkinitcpio.conf ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block cicada-crypt filesystems fsck)/' \
    /etc/mkinitcpio.conf
fi
# The live image's mkinitcpio presets are archiso's: they point at a squashfs
# that does not exist on this disk. cicada-install excludes them from the copy,
# which leaves `mkinitcpio -P` with no preset to act on and therefore NO
# INITRAMFS AT ALL — an unbootable machine. Write the stock preset ourselves
# rather than depend on a package having replaced it.
mkdir -p /etc/mkinitcpio.d
for kver in linux linux-hardened; do
  [[ -f "/boot/vmlinuz-${kver}" ]] || [[ "${kver}" == linux ]] || continue
  preset="/etc/mkinitcpio.d/${kver}.preset"
  if [[ ! -f "${preset}" ]] || grep -q archiso "${preset}" 2>/dev/null; then
    cat > "${preset}" <<PRESET
# Written by cicada-install. The live image ships archiso presets, which build
# an initramfs for booting a squashfs off USB — not for this disk.
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${kver}"
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-${kver}.img"
fallback_image="/boot/initramfs-${kver}-fallback.img"
fallback_options="-S autodetect"
PRESET
  fi
done
rm -f /etc/mkinitcpio.conf.d/archiso.conf

mkinitcpio -P
# An install that produced no initramfs boots to a kernel panic, and the failure
# is silent until the machine is rebooted with the USB already pulled. Refuse.
[[ -f /boot/initramfs-linux.img || -f /boot/initramfs-linux-hardened.img ]] \
  || { echo "FATAL: mkinitcpio produced no initramfs — this disk would not boot" >&2; exit 1; }

bootctl install --esp-path=/boot

mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf <<EOF
default cicada.conf
timeout 3
console-mode max
editor no
EOF

# lsm= is not decoration. Arch's stock `linux` builds AppArmor in but leaves it
# OUT of the default CONFIG_LSM list, so `systemctl enable apparmor.service`
# succeeds, the unit reports active, `aa-status` reports profiles loaded — and
# the LSM is not in the stack, enforcing nothing. Naming the full list here makes
# the boot fail loudly (unknown LSM) rather than quietly, and pins the order
# across both the hardened and the stock fallback entry.
# lockdown must stay in the list: the hardened entry appends lockdown=confidentiality.
LSM="landlock,lockdown,yama,integrity,apparmor,bpf"
CMDLINE="cryptdevice=UUID=${CICADA_LUKS_UUID}:cicada root=UUID=${CICADA_ROOT_UUID} rw quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 intel_iommu=on,igfx_off iommu.passthrough=0 init_on_alloc=1 init_on_free=1 ibt=on shstk=on lsm=${LSM}"
if [[ -n "${CICADA_BTRFS_SUBVOL:-}" ]]; then
  CMDLINE="${CMDLINE} rootflags=subvol=${CICADA_BTRFS_SUBVOL}"
fi

# The command line has to live in a file, not just in loader entries, because a
# UKI bakes it into the signed image and reads it from here. Keeping one source
# means the type-1 fallback and the UKI can never disagree about how this machine
# boots. cicada-uki appends lockdown=confidentiality for the hardened kernel.
mkdir -p /etc/kernel
printf '%s\n' "${CMDLINE}" > /etc/kernel/cmdline
chmod 644 /etc/kernel/cmdline

ucode=""
[[ -f /boot/intel-ucode.img ]] && ucode="initrd /intel-ucode.img"
[[ -f /boot/amd-ucode.img ]] && ucode="${ucode}"$'\n'"initrd /amd-ucode.img"

# Default etched kernel: linux-hardened + lockdown when present.
# Fallback entry: stock linux for MBA Broadcom (wl) and other out-of-tree drivers.
if [[ -f /boot/vmlinuz-linux-hardened ]]; then
  cat > /boot/loader/entries/cicada.conf <<EOF
title Cicada.OS
linux /vmlinuz-linux-hardened
${ucode}
initrd /initramfs-linux-hardened.img
options ${CMDLINE} lockdown=confidentiality
EOF
  cat > /boot/loader/entries/cicada-wifi.conf <<EOF
title Cicada.OS (Wi-Fi / Broadcom)
linux /vmlinuz-linux
${ucode}
initrd /initramfs-linux.img
options ${CMDLINE}
EOF
  rm -f /boot/loader/entries/cicada-hardened.conf
else
  cat > /boot/loader/entries/cicada.conf <<EOF
title Cicada.OS
linux /vmlinuz-linux
${ucode}
initrd /initramfs-linux.img
options ${CMDLINE}
EOF
fi

# Unified kernel images. The type-1 entries above are written first and on
# purpose: they are the thing that boots this machine if the UKI build fails, and
# cicada-uki only deletes them once every UKI has been built AND verified to be a
# real PE carrying .linux/.initrd/.cmdline.
#
# This is not a nicety. Without a UKI, sbctl signs vmlinuz and nothing else — the
# initramfs is a cpio and the loader entry is a text file, neither of which can
# hold a signature. An evil maid appends init=/bin/sh to cicada.conf and Secure
# Boot waves it through, because the kernel it checked was never modified. It is
# also what makes PCR 11 exist to seal against, so it is the difference between
# the Tier 2 the README promises and the Tier 1 that was actually shipping.
/usr/local/bin/cicada-uki build || {
  echo "==> WARNING: no unified kernel image was built."
  echo "    This machine will boot, but the kernel command line and the"
  echo "    initramfs are NOT covered by Secure Boot, and there is no PCR 11"
  echo "    to seal the disk against. Run 'cicada-uki status' after first boot."
}

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

# linux-hardened is not on the live ISO any more: nothing on it could boot that
# kernel, and it was most of what pushed the image over GitHub's 2 GiB cap. On a
# network install pacstrap already pulled it. On an offline install it is simply
# absent, so fetch it if there is a network and say so clearly if there is not —
# a missing hardened boot entry reduces protection, it does not leak anything,
# so per the design rule it degrades visibly rather than failing the install.
if [[ ! -f /boot/vmlinuz-linux-hardened ]]; then
  if pacman -Sy --noconfirm --needed linux-hardened >/dev/null 2>&1; then
    echo "==> linux-hardened installed; rebuilding boot entries"
    mkinitcpio -P || true
  else
    cat <<'HARDENEOF'
==> NOTE: this machine has the stock kernel only.

    linux-hardened is not on the live ISO (nothing there can boot it), and there
    was no network to fetch it during install. Everything else is in force; what
    is missing is the hardened boot entry and lockdown=confidentiality.

    Add it later with:  sudo pacman -S linux-hardened && sudo cicada-uki build
HARDENEOF
  fi
fi

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

# Must run AFTER the chown above, which would otherwise hand the directory back
# to the user. A user override beats a system one, so without this every Flatpak
# permission floor is one command away from being removed.
[[ -x /usr/local/lib/cicada/lock-flatpak-overrides.sh ]] \
  && /usr/local/lib/cicada/lock-flatpak-overrides.sh /home/cicada || true

systemctl enable NetworkManager.service
systemctl enable nftables.service
systemctl enable usbguard.service || true
systemctl enable apparmor.service || true
systemctl enable cicada-locked-reboot.timer || true
# The installed system needs firstboot too: it is what initialises the seal log
# and the device attestation key. Previously the unit lived only in the live
# overlay, so on a real install the binary shipped but nothing ever ran it.
systemctl enable cicada-firstboot.service || true
# Syscall filter for every cicada-run scope. Generated per boot into /run so the
# table always matches the running kernel's uapi header.
systemctl enable cicada-seccomp.service || true
# Privileged handler for the session duress credential. hyprlock is not setuid,
# so the PAM hook at the lock screen runs unprivileged and forwards to this
# socket; without it, typing the duress password at the lock screen does nothing.
systemctl enable cicada-duress.socket || true
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
HOME_URL="https://github.com/kpres12/Cicada.OS"
DOCUMENTATION_URL="https://github.com/kpres12/Cicada.OS"
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
HOME_URL="https://github.com/kpres12/Cicada.OS"
DOCUMENTATION_URL="https://github.com/kpres12/Cicada.OS"
LOGO=cicada
EOF

# greeter user for greetd (package usually creates it; belt and braces)
id greeter >/dev/null 2>&1 || useradd -r -s /usr/bin/nologin -M -d /var/lib/greetd greeter 2>/dev/null || true
systemctl enable greetd.service || true
# greetd owns VT1 — do not fight it with getty autologin
systemctl disable getty@tty1.service 2>/dev/null || true
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
# Drop Install/Etch icon from the etched desktop (live-only surface). Clear it
# from skel too, or the next account created on this box gets an Etch icon that
# only ever made sense from the USB. install.desktop is a pre-0.1 duplicate of
# etch.desktop — still removed so upgraded images do not keep a stale twin.
rm -f /home/cicada/Desktop/install.desktop \
      /home/cicada/Desktop/etch.desktop \
      /etc/skel/Desktop/install.desktop \
      /etc/skel/Desktop/etch.desktop 2>/dev/null || true

echo "==> chroot done host=${HOST} luks=${CICADA_LUKS_UUID}"
