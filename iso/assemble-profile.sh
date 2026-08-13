#!/usr/bin/env bash
# Assemble a mkarchiso profile: official releng + Cicada overlay.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${CICADA_PROFILE_DIR:-${ROOT}/work/profile}"
RELENG="${CICADA_RELENG:-}"

if [[ -z "${RELENG}" ]]; then
  if [[ -d /usr/share/archiso/configs/releng ]]; then
    RELENG=/usr/share/archiso/configs/releng
  elif [[ -d "${ROOT}/vendor/archiso/configs/releng" ]]; then
    RELENG="${ROOT}/vendor/archiso/configs/releng"
  else
    echo "error: archiso releng profile not found." >&2
    echo "  Install archiso, or clone it into vendor/archiso." >&2
    exit 1
  fi
fi

echo "==> releng:  ${RELENG}"
echo "==> profile: ${PROFILE}"

rm -rf "${PROFILE}"
mkdir -p "${PROFILE}"
rsync -a "${RELENG}/" "${PROFILE}/"

# Merge package lists: releng + cicada extras - excludes
python3 - "${PROFILE}/packages.x86_64" \
  "${ROOT}/iso/packages.cicada.x86_64" \
  "${ROOT}/iso/packages.exclude" \
  "${ROOT}/iso/packages.optional.x86_64" <<'PY'
import sys
from pathlib import Path

releng, extra, exclude, optional = map(Path, sys.argv[1:5])

def pkgs(path: Path) -> list[str]:
    out = []
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out

exclude_set = set(pkgs(exclude))
merged = []
seen = set()
for name in pkgs(releng) + pkgs(extra) + (pkgs(optional) if __import__("os").environ.get("CICADA_FULL") == "1" else []):
    if name in exclude_set or name in seen:
        continue
    seen.add(name)
    merged.append(name)
releng.write_text("\n".join(merged) + "\n")
print(f"==> packages: {len(merged)} (full={__import__('os').environ.get('CICADA_FULL', '0')})")
PY

# QEMU/Rosetta: pacstrap inside the builder also needs the sandbox off
python3 - "${PROFILE}/pacman.conf" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
lines = []
for line in text.splitlines(True):
    if line.startswith("DownloadUser"):
        lines.append("#" + line)
    else:
        lines.append(line)
text = "".join(lines)
if "DisableSandbox" not in text:
    text += "\nDisableSandbox\n"
path.write_text(text)
print("==> pacman sandbox disabled for emulated builds")
PY
rsync -a "${ROOT}/iso/overlay/airootfs/" "${PROFILE}/airootfs/"
rsync -a "${ROOT}/packages/cicada-defaults/files/" "${PROFILE}/airootfs/"
rsync -a "${ROOT}/packages/cicada-shell/files/" "${PROFILE}/airootfs/"
rsync -a "${ROOT}/packages/cicada-profiles/files/" "${PROFILE}/airootfs/"
rsync -a "${ROOT}/packages/cicada-run/files/" "${PROFILE}/airootfs/"
rsync -a "${ROOT}/packages/cicada-install/files/" "${PROFILE}/airootfs/"

# Live user must get skel (dock, hypr, scopes). Overlay only ships .bash_profile.
mkdir -p "${PROFILE}/airootfs/home/cicada"
rsync -a "${PROFILE}/airootfs/etc/skel/" "${PROFILE}/airootfs/home/cicada/"
mkdir -p "${PROFILE}/airootfs/usr/share/cicada"
cp "${ROOT}/docs/USER.md" "${PROFILE}/airootfs/usr/share/cicada/FIRST-BOOT.txt"
cp "${ROOT}/docs/USER.md" "${PROFILE}/airootfs/etc/skel/FIRST-BOOT.txt" 2>/dev/null || true

# Releng enables mDNS; Cicada does not. Drop the archiso resolved drop-in if present.
rm -f "${PROFILE}/airootfs/etc/systemd/resolved.conf.d/archiso.conf"
rm -f "${PROFILE}/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service"
ln -sfn /dev/null "${PROFILE}/airootfs/etc/systemd/system/sshd.service"

# Enable Cicada units
wants="${PROFILE}/airootfs/etc/systemd/system/multi-user.target.wants"
mkdir -p "${wants}"
ln -sfn /etc/systemd/system/cicada-radios-off.service "${wants}/cicada-radios-off.service"
ln -sfn /etc/systemd/system/cicada-firstboot.service "${wants}/cicada-firstboot.service"
ln -sfn /etc/systemd/system/cicada-amnesic.service "${wants}/cicada-amnesic.service"
ln -sfn /usr/lib/systemd/system/nftables.service "${wants}/nftables.service"

# Desktop Wi-Fi: NetworkManager owns the stack. networkd+iwd-standalone fight NM.
rm -f "${wants}/systemd-networkd.service" "${wants}/iwd.service"
rm -f "${PROFILE}/airootfs/etc/systemd/system/dbus-org.freedesktop.network1.service"
rm -f "${PROFILE}/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
rm -f "${PROFILE}/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
ln -sfn /usr/lib/systemd/system/NetworkManager.service "${wants}/NetworkManager.service"
# USBGuard on live will block the Air's USB HID keyboard/trackpad if it
# starts before they enumerate. Installed systems enable it in install-chroot.
rm -f "${wants}/usbguard.service"
ln -sfn /usr/lib/systemd/system/apparmor.service "${wants}/apparmor.service"
mkdir -p "${PROFILE}/airootfs/etc/systemd/system/timers.target.wants"
ln -sfn /etc/systemd/system/cicada-locked-reboot.timer \
  "${PROFILE}/airootfs/etc/systemd/system/timers.target.wants/cicada-locked-reboot.timer"

# Brand the ISO metadata without rewriting releng bootloader machinery
python3 - "${PROFILE}/profiledef.sh" <<'PY'
import pathlib, sys, datetime, os
path = pathlib.Path(sys.argv[1])
text = path.read_text()
repls = {
    'iso_name="archlinux"': 'iso_name="cicada"',
    'iso_label="ARCH_': 'iso_label="CICADA_',
    'iso_publisher="Arch Linux <https://archlinux.org>"': 'iso_publisher="Cicada.OS"',
    'iso_application="Arch Linux Live/Rescue DVD"': 'iso_application="Cicada.OS Live/Install"',
    'install_dir="arch"': 'install_dir="cicada"',
}
for a, b in repls.items():
    if a not in text:
        raise SystemExit(f"profiledef.sh missing expected token: {a}")
    text = text.replace(a, b, 1)
# Force Intel/x86_64 even when the Docker host is Apple Silicon
if 'arch="' not in text:
    text = text.replace('buildmodes=(\'iso\')', "arch=\"x86_64\"\nbuildmodes=('iso')", 1)
# Extra file_permissions for Cicada binaries
needle = '  ["/usr/local/bin/livecd-sound"]="0:0:755"\n)'
insert = '''  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/cicada-firstboot"]="0:0:755"
  ["/usr/local/bin/cicada-radios-off"]="0:0:755"
  ["/usr/local/bin/cicada-radios-toggle"]="0:0:755"
  ["/usr/local/bin/cicada-profile"]="0:0:755"
  ["/usr/local/bin/cicada-scopes"]="0:0:755"
  ["/usr/local/bin/cicada-wifi"]="0:0:755"
  ["/usr/local/bin/cicada-lock"]="0:0:755"
  ["/usr/local/bin/cicada-vpn"]="0:0:755"
  ["/usr/local/bin/cicada-locked-reboot"]="0:0:755"
  ["/usr/local/bin/cicada-sbctl-sign"]="0:0:755"
  ["/usr/local/bin/cicada-run"]="0:0:755"
  ["/usr/local/bin/cicada-install"]="0:0:755"
  ["/usr/local/bin/cicada-duress-enroll"]="0:0:755"
  ["/usr/local/bin/cicada-seal"]="0:0:755"
  ["/usr/local/bin/cicada-attest"]="0:0:755"
  ["/usr/local/bin/cicada-beacon"]="0:0:755"
  ["/usr/local/bin/cicada-auth"]="0:0:755"
  ["/usr/local/bin/cicada-tpm-enroll"]="0:0:755"
  ["/usr/local/bin/cicada-sbctl-enroll"]="0:0:755"
  ["/usr/local/bin/cicada-backup"]="0:0:755"
  ["/usr/local/bin/cicada-quote-verify"]="0:0:755"
  ["/usr/local/lib/cicada/install-chroot.sh"]="0:0:755"
  ["/usr/local/bin/chromium"]="0:0:755"
  ["/usr/local/bin/keepassxc"]="0:0:755"
  ["/usr/local/bin/cicada-panic"]="0:0:755"
  ["/usr/local/bin/cicada-amnesic"]="0:0:755"
  ["/usr/local/bin/cicada-profile-helper"]="0:0:755"
  ["/etc/sudoers.d/cicada-profile"]="0:0:440"
  ["/etc/shadow"]="0:0:400"
  ["/home/cicada"]="1000:1000:750"
)'''
if needle not in text:
    raise SystemExit("profiledef.sh file_permissions block changed upstream")
text = text.replace(needle, insert, 1)
path.write_text(text)
print("==> profiledef.sh branded")
PY

# Rebrand bootloader titles only — never rewrite archisobasedir / %ARCHISO_UUID%
python3 - "${PROFILE}" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
repls = (
    ("Arch Linux install medium", "Cicada.OS live"),
    ("Arch Linux", "Cicada.OS"),
)
count = 0
for folder in ("efiboot", "syslinux", "grub"):
    base = root / folder
    if not base.exists():
        continue
    for path in base.rglob("*"):
        if path.suffix not in {".cfg", ".conf"} or not path.is_file():
            continue
        text = path.read_text()
        new = text
        for a, b in repls:
            new = new.replace(a, b)
        if new != text:
            path.write_text(new)
            count += 1
print(f"==> rebranded {count} bootloader files")
PY

# IOMMU + zero-on-free on every live entry. lockdown only on the hardened clone (breaks some out-of-tree modules).
python3 - "${PROFILE}" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
# igfx_off: Apple Intel iGPU + IOMMU otherwise never leaves the text console.
extra = " intel_iommu=on,igfx_off iommu.passthrough=0 init_on_alloc=1 init_on_free=1 ibt=on shstk=on"
count = 0
for path in (root / "efiboot").rglob("*.conf") if (root / "efiboot").exists() else []:
    text = path.read_text()
    if "archisosearchuuid=%ARCHISO_UUID%" not in text:
        continue
    if "intel_iommu=" in text:
        continue
    path.write_text(text.replace(
        "archisosearchuuid=%ARCHISO_UUID%",
        "archisosearchuuid=%ARCHISO_UUID%" + extra,
        1,
    ))
    count += 1
print(f"==> DMA/zero-on-free cmdline on {count} UEFI entries")
PY

# Second boot entry: linux-hardened. Default entry stays `linux` so MBA Broadcom (broadcom-wl) works.
python3 - "${PROFILE}" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
entries = root / "efiboot/loader/entries"
src = next(entries.glob("01-*.conf"), None) if entries.exists() else None
if src is None:
    print("==> no UEFI linux entry to clone for hardened kernel")
else:
    text = src.read_text()
    text = text.replace("vmlinuz-linux\n", "vmlinuz-linux-hardened\n")
    text = text.replace("initramfs-linux.img", "initramfs-linux-hardened.img")
    text = text.replace("sort-key 01", "sort-key 03")
    text = text.replace("Cicada.OS live", "Cicada.OS live (linux-hardened)")
    if "lockdown=" not in text:
        text = text.replace(
            "archisosearchuuid=%ARCHISO_UUID%",
            "archisosearchuuid=%ARCHISO_UUID% lockdown=confidentiality",
        )
    dest = entries / "03-cicada-hardened.conf"
    dest.write_text(text)
    print(f"==> hardened boot entry {dest.name}")

# Tails-shaped live: copy ISO into RAM so the stick can leave; yank still panic-reboots.
src = next(entries.glob("01-*.conf"), None) if entries.exists() else None
if src is not None:
    text = src.read_text()
    text = text.replace("sort-key 01", "sort-key 04")
    text = text.replace("Cicada.OS live", "Cicada.OS live (amnesic — copy to RAM)")
    if "copytoram" not in text:
        text = text.replace(
            "archisosearchuuid=%ARCHISO_UUID%",
            "archisosearchuuid=%ARCHISO_UUID% copytoram cow_spacesize=2G",
        )
    dest = entries / "00-cicada-amnesic.conf"
    dest.write_text(text)
    print(f"==> amnesic copytoram boot entry {dest.name}")
PY

chmod 755 "${PROFILE}/airootfs/usr/local/bin/"* 2>/dev/null || true
chmod 755 "${PROFILE}/airootfs/usr/local/lib/cicada/"* 2>/dev/null || true
chmod 440 "${PROFILE}/airootfs/etc/sudoers.d/cicada-profile" 2>/dev/null || true
chmod 400 "${PROFILE}/airootfs/etc/shadow"

echo "==> assembled ${PROFILE}"
