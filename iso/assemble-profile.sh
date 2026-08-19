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
chmod +x "${PROFILE}/airootfs/home/cicada/Desktop/"*.desktop 2>/dev/null || true
chmod +x "${PROFILE}/airootfs/etc/skel/Desktop/"*.desktop 2>/dev/null || true
# Ship the Wi-Fi diagnostic on the medium — it is needed on the Air, where
# there is no network to fetch it over. That is the whole point of it.
install -Dm755 "${ROOT}/tests/wifi-diag.sh" \
  "${PROFILE}/airootfs/usr/local/bin/cicada-wifi-diag"
install -Dm755 "${ROOT}/tests/boot-verify.sh" \
  "${PROFILE}/airootfs/usr/local/bin/cicada-verify"

# Build stamp. Without this there is no way to tell a freshly built ISO from one
# sitting in out/ from three commits ago — which is exactly how a known-fixed
# bug gets re-tested on a stale image. Compare against `git rev-parse HEAD`.
mkdir -p "${PROFILE}/airootfs/usr/share/cicada"
{
  printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if git -C "${ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'commit=%s\n' "$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if [[ -n "$(git -C "${ROOT}" status --porcelain 2>/dev/null)" ]]; then
      printf 'tree=dirty\n'
    else
      printf 'tree=clean\n'
    fi
  else
    printf 'commit=not-a-git-checkout\ntree=unknown\n'
  fi
} > "${PROFILE}/airootfs/usr/share/cicada/BUILD-ID"

# Prefer [cicada-stable] + embed local repo when a prior/current channel build exists.
mkdir -p "${PROFILE}/airootfs/var/cache/cicada/repo" \
         "${PROFILE}/airootfs/usr/local/lib/cicada"
if [[ -x "${ROOT}/packages/cicada-defaults/files/usr/local/lib/cicada/cicada-channel-enable.sh" ]]; then
  # Patch the eventual live pacman.conf placeholder; pacstrap may overwrite — firstboot re-runs enable.
  mkdir -p "${PROFILE}/airootfs/etc/pacman.d"
  cp -a "${ROOT}/packages/cicada-defaults/files/etc/pacman.d/"* \
    "${PROFILE}/airootfs/etc/pacman.d/" 2>/dev/null || true
fi
# The channel repo is the tested Arch snapshot — ~2 GiB. Embedding it would take
# the ISO from 3 GiB to over 5 and duplicate every package already inside the
# squashfs, to no purpose: an update needs the network anyway, so it can reach
# the hosted mirror. The directory ships empty and cicada-channel-enable omits
# the file:// Server unless a database is genuinely present, so pacman never
# tries to sync a repo that is not there.
#
# CICADA_EMBED_CHANNEL=1 restores the old behaviour for a fully offline build.
if [[ "${CICADA_EMBED_CHANNEL:-0}" == "1" ]]; then
  for repo_src in "${ROOT}/out/channel-repo" "${ROOT}/channel/repo"; do
    if [[ -d "${repo_src}" ]] && compgen -G "${repo_src}/cicada-stable.db*" >/dev/null 2>&1; then
      echo "==> embedding cicada-stable repo from ${repo_src} (CICADA_EMBED_CHANNEL=1)"
      rsync -a "${repo_src}/" "${PROFILE}/airootfs/var/cache/cicada/repo/"
      break
    fi
  done
fi
# hide-arch-desktops runs on firstboot / install-chroot (needs the real airootfs package set).

# Channel pin, so `cicada-update` can name the snapshot this image was cut from
# instead of printing "channel pin: unknown".
# BSD install (macOS, where this assembles) has no -D, so create the parent
# first rather than relying on it.
if [[ -f "${ROOT}/channel/CURRENT" ]]; then
  mkdir -p "${PROFILE}/airootfs/usr/share/cicada/channel"
  install -m644 "${ROOT}/channel/CURRENT" \
    "${PROFILE}/airootfs/usr/share/cicada/channel/CURRENT"
fi

mkdir -p "${PROFILE}/airootfs/usr/share/cicada"
cp "${ROOT}/docs/USER.md" "${PROFILE}/airootfs/usr/share/cicada/FIRST-BOOT.txt"
cp "${ROOT}/docs/USER.md" "${PROFILE}/airootfs/etc/skel/FIRST-BOOT.txt" 2>/dev/null || true

# Also seed Hidden overrides for known Arch apps into the profile so live boots
# are sealed before firstboot runs (paths relative to PROFILE airootfs).
mkdir -p "${PROFILE}/airootfs/usr/local/share/applications"
for base in kitty.desktop pcmanfm-qt.desktop thunar.desktop org.kde.dolphin.desktop \
            alacritty.desktop foot.desktop org.gnome.Nautilus.desktop \
            nm-connection-editor.desktop; do
  cat > "${PROFILE}/airootfs/usr/local/share/applications/${base}" <<EOF
[Desktop Entry]
Hidden=true
NoDisplay=true
Name=Hidden by Cicada (${base})
Type=Application
EOF
done
# Releng enables mDNS; Cicada does not. Drop the archiso resolved drop-in if present.
rm -f "${PROFILE}/airootfs/etc/systemd/resolved.conf.d/archiso.conf"
rm -f "${PROFILE}/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service"
ln -sfn /dev/null "${PROFILE}/airootfs/etc/systemd/system/sshd.service"

# Enable Cicada units
wants="${PROFILE}/airootfs/etc/systemd/system/multi-user.target.wants"
mkdir -p "${wants}"
ln -sfn /etc/systemd/system/cicada-firstboot.service "${wants}/cicada-firstboot.service"
ln -sfn /etc/systemd/system/cicada-amnesic.service "${wants}/cicada-amnesic.service"
ln -sfn /etc/systemd/system/cicada-watchdog.service "${wants}/cicada-watchdog.service"
ln -sfn /etc/systemd/system/cicada-tor-netns.service "${wants}/cicada-tor-netns.service"
# Builds the bwrap syscall filter into /run before anything can be launched.
# Without it every scope falls back to namespaces-only, which cicada-run reports.
ln -sfn /etc/systemd/system/cicada-seccomp.service "${wants}/cicada-seccomp.service"
mkdir -p "${PROFILE}/airootfs/etc/systemd/system/poweroff.target.wants" "${PROFILE}/airootfs/etc/systemd/system/reboot.target.wants"
for t_ in poweroff reboot; do ln -sfn /etc/systemd/system/cicada-memwipe.service "${PROFILE}/airootfs/etc/systemd/system/${t_}.target.wants/cicada-memwipe.service"; done
ln -sfn /etc/systemd/system/cicada-yank-watch.service "${wants}/cicada-yank-watch.service"
ln -sfn /usr/lib/systemd/system/nftables.service "${wants}/nftables.service"

# Desktop Wi-Fi: NetworkManager owns the stack. networkd+iwd-standalone fight NM.
rm -f "${wants}/systemd-networkd.service" "${wants}/iwd.service"
rm -f "${PROFILE}/airootfs/etc/systemd/system/dbus-org.freedesktop.network1.service"
rm -f "${PROFILE}/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
rm -f "${PROFILE}/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
ln -sfn /usr/lib/systemd/system/NetworkManager.service "${wants}/NetworkManager.service"
# Live: USBGuard with HID allow (MBA keyboard/trackpad are USB). AppArmor stays install-only.
ln -sfn /usr/lib/systemd/system/usbguard.service "${wants}/usbguard.service"
rm -f "${wants}/apparmor.service"
# cicada-beacon.timer is deliberately NOT linked here. A live ISO has no pinned
# witness and a boot hash that is the same on every copy of the image, so a
# beacon from it carries no information and would train someone to ignore the
# one that matters. cicada-firstrun offers it after an install, once there is a
# machine identity to make a statement about. See docs/BEACON.md.
mkdir -p "${PROFILE}/airootfs/etc/systemd/system/timers.target.wants"
ln -sfn /etc/systemd/system/cicada-locked-reboot.timer \
  "${PROFILE}/airootfs/etc/systemd/system/timers.target.wants/cicada-locked-reboot.timer"

# --- carve out archiso's installer-ISO surface ------------------------------
# releng enables a set of services appropriate for a general-purpose Arch
# installer that boots in clouds and hypervisors. Cicada inherits all of it by
# rsyncing the releng airootfs, so anything not explicitly removed here ships
# enabled. Each removal below is a decision, not tidying.

# Hypervisor guest agents are a host-to-guest control channel by design:
# clipboard capture, file transfer, and command execution initiated by whoever
# owns the hypervisor. That is a reasonable convenience for a VM you own and an
# anti-feature for an OS whose threat model includes an adversary controlling
# the machine underneath you. People WILL test Cicada in a VM; they should not
# silently get a host with read access to the guest.
rm -f "${wants}/vboxservice.service" \
      "${wants}/vmtoolsd.service" \
      "${wants}/vmware-vmblock-fuse.service" \
      "${wants}/hv_fcopy_daemon.service" \
      "${wants}/hv_kvp_daemon.service" \
      "${wants}/hv_vss_daemon.service" \
      "${wants}/qemu-guest-agent.service"

# cloud-init is excluded from the package list, but releng still ships the enable
# symlinks — dangling units that would fetch instance metadata from a cloud
# provider if the package ever came back. Remove the whole target.
rm -rf "${PROFILE}/airootfs/etc/systemd/system/cloud-init.target.wants"

# ModemManager probes every serial-looking device with AT commands. On a laptop
# with no WWAN that is pure attack surface, and it interferes with USB serial.
rm -f "${wants}/ModemManager.service"

# choose-mirror reads a kernel cmdline parameter and reaches out to fetch a
# mirrorlist: a network callout during early boot, before the user has chosen
# to be on a network at all.
rm -f "${wants}/choose-mirror.service"

# pcscd is a smartcard daemon listening on a socket for any reader plugged in.
# Nothing in Cicada uses it; it is a USB-triggered attack surface.
rm -f "${PROFILE}/airootfs/etc/systemd/system/sockets.target.wants/pcscd.socket"

# Plaintext NTP at boot leaks the IP and lets anyone on-path move the clock —
# which is how certificate expiry checks get bypassed. Replaced by chrony with
# NTS (authenticated time). See etc/chrony.conf.
rm -f "${PROFILE}/airootfs/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service" \
      "${PROFILE}/airootfs/etc/systemd/system/sysinit.target.wants/systemd-time-wait-sync.service"
ln -sfn /usr/lib/systemd/system/chronyd.service "${wants}/chronyd.service"

# livecd-talk (screen reader) is deliberately KEPT: it only activates with
# accessibility=on, and stripping accessibility from a privacy OS would exclude
# the people least able to shop around for an alternative.

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
  ["/usr/local/bin/cicada-link"]="0:0:755"
  ["/usr/local/bin/cicada-comms"]="0:0:755"
  ["/usr/local/bin/cicada-auth"]="0:0:755"
  ["/usr/local/bin/cicada-tpm-enroll"]="0:0:755"
  ["/usr/local/bin/cicada-sbctl-enroll"]="0:0:755"
  ["/usr/local/bin/cicada-uki"]="0:0:755"
  ["/usr/local/bin/cicada-luks-header"]="0:0:755"
  ["/usr/local/bin/cicada-backup"]="0:0:755"
  ["/usr/local/bin/cicada-quote-verify"]="0:0:755"
  ["/usr/local/bin/cicada-keyfile-enroll"]="0:0:755"
  ["/usr/local/bin/cicada-hw-trust"]="0:0:755"
  ["/usr/local/bin/cicada-watchdog"]="0:0:755"
  ["/usr/local/bin/cicada-memwipe"]="0:0:755"
  ["/usr/local/bin/cicada-logs"]="0:0:755"
  ["/usr/local/bin/cicada-portal"]="0:0:755"
  ["/usr/local/bin/cicada-verify"]="0:0:755"
  ["/usr/local/bin/cicada-wifi-diag"]="0:0:755"
  ["/usr/local/bin/cicada-status"]="0:0:755"
  ["/usr/local/bin/cicada-firstrun"]="0:0:755"
  ["/usr/local/bin/cicada-etch"]="0:0:755"
  ["/usr/local/bin/cicada-tor"]="0:0:755"
  ["/usr/local/bin/cicada-tor-netns"]="0:0:755"
  ["/usr/local/bin/cicada-netns-helper"]="0:0:755"
  ["/etc/sudoers.d/cicada-netns"]="0:0:440"
  ["/usr/local/bin/cicada-duress-check"]="0:0:700"
  ["/usr/local/lib/cicada/install-chroot.sh"]="0:0:755"
  ["/usr/local/bin/chromium"]="0:0:755"
  ["/usr/local/bin/keepassxc"]="0:0:755"
  ["/usr/local/bin/cicada-panic"]="0:0:755"
  ["/usr/local/bin/cicada-amnesic"]="0:0:755"
  ["/usr/local/bin/cicada-yank-watch"]="0:0:755"
  ["/usr/local/bin/cicada-settings"]="0:0:755"
  ["/usr/local/bin/cicada-dock"]="0:0:755"
  ["/usr/local/bin/cicada-wofi"]="0:0:755"
  ["/usr/local/bin/cicada-files"]="0:0:755"
  ["/usr/local/bin/cicada-desktop-trust"]="0:0:755"
  ["/usr/local/bin/cicada-profile-helper"]="0:0:755"
  ["/usr/local/bin/cicada-av-kill"]="0:0:755"
  ["/usr/local/lib/cicada/hide-arch-desktops.sh"]="0:0:755"
  ["/usr/local/lib/cicada/cicada-channel-enable.sh"]="0:0:755"
  ["/usr/local/lib/cicada/strip-setuid.sh"]="0:0:755"
  ["/usr/local/lib/cicada/heal-helium.sh"]="0:0:755"
  ["/usr/local/lib/cicada/cicada-seccomp-gen.sh"]="0:0:755"
  ["/etc/sudoers.d/cicada-profile"]="0:0:440"
  ["/etc/greetd/config.toml"]="0:0:644"
  ["/usr/share/wayland-sessions/cicada.desktop"]="0:0:644"
  ["/etc/shadow"]="0:0:400"
  ["/home/cicada"]="1000:1000:750"
  ["/home/cicada/Desktop/web.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/wifi.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/files.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/settings.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/term.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/start-here.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/doom.desktop"]="1000:1000:755"
  ["/home/cicada/Desktop/power.desktop"]="1000:1000:755"
  ["/usr/local/bin/cicada-doom"]="0:0:755"
  ["/usr/local/bin/cicada-power"]="0:0:755"
  ["/usr/local/bin/cicada-pkg"]="0:0:755"
  ["/usr/local/bin/cicada-pkg-helper"]="0:0:755"
  ["/usr/local/bin/cicada-wallpaper"]="0:0:755"
  ["/usr/local/bin/cicada-wallpapers"]="0:0:755"
  ["/usr/local/bin/cicada-telemetry"]="0:0:755"
  ["/usr/share/cicada/quickshell/pattern-bay/cache.sh"]="0:0:755"
  ["/usr/share/cicada/quickshell/pattern-bay/shell.qml"]="0:0:644"
  ["/usr/share/cicada/hyprlock-fallback.conf"]="0:0:644"
  ["/usr/local/bin/cicada-session"]="0:0:755"
  ["/usr/local/bin/cicada-session-sway"]="0:0:755"
  ["/usr/local/bin/cicada-session-niri"]="0:0:755"
  ["/usr/local/bin/cicada-login"]="0:0:755"
  ["/usr/local/bin/cicada-update"]="0:0:755"
  ["/usr/local/bin/cicada-malloc"]="0:0:755"
  ["/usr/local/bin/cicada-usb-gate"]="0:0:755"
  ["/usr/local/bin/cicada-banner"]="0:0:755"
  ["/usr/local/bin/cicada-brightness"]="0:0:755"
  ["/usr/local/bin/cicada-tor-browser"]="0:0:755"
  ["/usr/share/wayland-sessions/cicada.desktop"]="0:0:644"
  ["/usr/share/wayland-sessions/cicada-sway.desktop"]="0:0:644"
  ["/usr/share/wayland-sessions/cicada-niri.desktop"]="0:0:644"
  ["/usr/share/cicada/wayland-sessions/cicada.desktop"]="0:0:644"
  ["/usr/share/cicada/wayland-sessions/cicada-sway.desktop"]="0:0:644"
  ["/usr/share/cicada/wayland-sessions/cicada-niri.desktop"]="0:0:644"
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
    ("Arch Linux install medium", "Cicada.OS"),
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

# Zero-on-free on every live entry. Do NOT put intel_iommu on the default
# desktop entry — Apple EFI + iGPU then never leaves the text console.
python3 - "${PROFILE}" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
extra = " quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 init_on_alloc=1 init_on_free=1 ibt=on shstk=on"
count = 0
for path in (root / "efiboot").rglob("*.conf") if (root / "efiboot").exists() else []:
    text = path.read_text()
    if "archisosearchuuid=%ARCHISO_UUID%" not in text:
        continue
    if "init_on_alloc=" in text:
        continue
    path.write_text(text.replace(
        "archisosearchuuid=%ARCHISO_UUID%",
        "archisosearchuuid=%ARCHISO_UUID%" + extra,
        1,
    ))
    count += 1
print(f"==> zero-on-free cmdline on {count} UEFI entries")
PY

# Live boot menu: two entries only.
#   01 — Cicada.OS (default; stick stays mounted; MBA-safe linux + wl)
#   02 — Cicada.OS (copy to RAM)
# Drop Arch speech / memtest. linux-hardened stays packaged for *install*, not the live picker.
python3 - "${PROFILE}" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
entries = root / "efiboot/loader/entries"
if not entries.exists():
    print("==> no efiboot entries dir")
    raise SystemExit(0)

for pattern in (
    "02-archiso-speech*.conf",
    "03-archiso-memtest*.conf",
    "*speech*.conf",
    "*memtest*.conf",
    "03-cicada-hardened.conf",
    "04-cicada-amnesic.conf",
):
    for p in entries.glob(pattern):
        p.unlink()
        print(f"==> removed boot entry {p.name}")

# Syslinux / GRUB often still list speech + memtest — strip those labels' menu items
for folder in ("syslinux", "grub"):
    base = root / folder
    if not base.exists():
        continue
    for path in base.rglob("*"):
        if not path.is_file() or path.suffix not in {".cfg", ".conf"}:
            continue
        text = path.read_text()
        # Best-effort: drop speech/memtest LABEL blocks is fragile; hide via title prefix skip
        # Releng syslinux uses INCLUDE — remove known includes if present
        new = text
        for line in (
            "INCLUDE archiso_speech*.cfg",
            "INCLUDE archiso_memtest*.cfg",
        ):
            pass
        for drop in ("archiso_speech64.cfg", "archiso_speech32.cfg", "archiso_memtest.cfg", "memtest"):
            # comment out include lines
            lines = []
            for ln in new.splitlines(True):
                if drop in ln and not ln.lstrip().startswith("#"):
                    lines.append("# cicada: " + ln)
                else:
                    lines.append(ln)
            new = "".join(lines)
        if new != text:
            path.write_text(new)
            print(f"==> scrubbed speech/memtest refs in {path.relative_to(root)}")

src = next(entries.glob("01-*.conf"), None)
if src is None:
    print("==> no 01- live entry")
else:
    lines = src.read_text().splitlines(True)
    for i, line in enumerate(lines):
        if line.startswith("title"):
            lines[i] = "title    Cicada.OS\n"
            break
    src.write_text("".join(lines))
    print(f"==> default entry {src.name} → Cicada.OS")

    amnesic_lines = src.read_text().splitlines(True)
    out = []
    for line in amnesic_lines:
        if line.startswith("title"):
            out.append("title    Cicada.OS (copy to RAM)\n")
        elif line.startswith("sort-key"):
            out.append("sort-key 02\n")
        else:
            out.append(line)
    amnesic = "".join(out)
    if "copytoram" not in amnesic:
        amnesic = amnesic.replace(
            "archisosearchuuid=%ARCHISO_UUID%",
            "archisosearchuuid=%ARCHISO_UUID% copytoram cow_spacesize=2G",
        )
    dest = entries / "02-cicada-ram.conf"
    dest.write_text(amnesic)
    print(f"==> amnesic entry {dest.name}")

loader = root / "efiboot/loader/loader.conf"
if loader.exists():
    text = loader.read_text()
    text = text.replace("timeout 15", "timeout 5")
    text = text.replace("timeout 8", "timeout 5")
    loader.write_text(text)
    print("==> loader timeout 5s; menu = Cicada.OS + copy-to-RAM only")

# Sanity: at most two UEFI linux-ish entries + no speech/memtest/hardened
left = sorted(p.name for p in entries.glob("*.conf"))
print("==> UEFI entries:", ", ".join(left))
if len(left) > 2:
    print("==> WARNING: more than 2 UEFI entries remain:", left)
PY

chmod 755 "${PROFILE}/airootfs/usr/local/bin/"* 2>/dev/null || true
chmod 755 "${PROFILE}/airootfs/usr/local/lib/cicada/"* 2>/dev/null || true
chmod 440 "${PROFILE}/airootfs/etc/sudoers.d/cicada-profile" 2>/dev/null || true
chmod 440 "${PROFILE}/airootfs/etc/sudoers.d/cicada-live" 2>/dev/null || true
chmod 440 "${PROFILE}/airootfs/etc/sudoers.d/cicada-netns" 2>/dev/null || true
chmod 400 "${PROFILE}/airootfs/etc/shadow"

echo "==> assembled ${PROFILE}"
