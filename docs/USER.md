# Cicada — what you do at the machine

This is the user sheet. Engineering notes live in other files under `docs/`.

You will see two different machines:

| You booted… | What it is |
|---|---|
| **Live USB** (Option-boot the ISO) | Demo / Tails-shaped. Overlay is RAM. Empty password. Unplug or reboot = gone. |
| **Installed disk** (`cicada-install`) | Daily driver. LUKS + a real login. Files survive reboot. |

---

## 1. Live USB (today)

1. Confirm the stick is the 250 GB **JACKSPARROW**, then flash (macOS will say the disk is unreadable — **Eject**, never Initialize).
2. Air: hold **Option (⌥)** → Cicada.
3. You are `cicada` with **no password**. Click the dock or **SETTINGS** on the top bar.
4. Click **WIFI**, pick a network. Telemetry stays off.
5. Windows **tile**. **CLOSE** on the bar or Alt+F4. Super+V floats one window.
6. **SETTINGS** has sound, brightness, **App permissions** (scopes), **Camera & microphone** (software kill), **Profiles** (Work UID), dock, lock.
7. **Web** is Helium. The launcher only shows Cicada apps — not the full Arch menu.

**Amnesic (Tails-shaped):** at the boot menu pick **Cicada.OS (copy to RAM)**. Needs more RAM. The stick can leave; yanking it force-reboots. Default **Cicada.OS** keeps the USB in (safer on 8GB Airs). Internal SSD is not mounted.

Do **not** enroll duress or TPM on the live USB. There is no LUKS yet.

When you want a real OS (files, wallpaper, Work UID): run **Install** — see §2. Live stays the beta/test stick.

---

## 2. Install (daily driver)

Wi‑Fi first (`pacstrap` needs network). Other USB/SSD in, not the live stick.

```bash
sudo cicada-install --list
sudo cicada-install --target /dev/sdX              # external
sudo cicada-install --target /dev/nvme0n1 --internal   # Framework-class only
```

Apple internal disks are refused.

You set:

1. **LUKS passphrase** — unlocks the whole disk at boot. This is the important secret.
2. **User password** for `cicada` — the login after the disk opens. Root is locked; use `sudo`.

Reboot, pick the install disk in firmware, type the LUKS passphrase, then log in as `cicada`.

---

## 3. First hour on the installed system

Open Terminal (dock). Nothing here is required for browsing; do it when you care.

```bash
sudo cicada-duress-enroll    # second disk passphrase; see below
sudo cicada-tpm-enroll       # skip / exit 2 on Apple EFI
sudo cicada-sbctl-enroll     # skip unless firmware is in Setup Mode
cicada-uki status            # is the boot image signed? (installer builds it)
cicada-attest                # copy ~/cicada-attest/device.pub onto a Pixel you own
```

`cicada-uki status` should show a ✓ per kernel and **no** leftover type-1
entries. Those entries are an editable copy of your kernel command line on an
unencrypted partition; the signed image exists so that editing it stops working.
If it reports none, run `sudo cicada-uki build`.

### Back up the LUKS header — read the warning first

The header holds the wrapped master key. Damage the first 16 MB of the disk and
everything on it is gone permanently; no passphrase recovers it. That matters
more here than elsewhere, because the duress passphrase and the 20-wrong-guess
cap both destroy keyslots *on purpose*.

The same backup undoes both of those wipes for anyone holding the file, and keeps
working with passphrases you later revoke. If you are more worried about coercion
than about hardware failure, not having one is a legitimate choice.

```bash
sudo cicada-luks-header backup /run/media/cicada/YOURUSB/cicada-header.img
```

Store it away from the laptop. It refuses to write to this disk or its EFI
partition, because a header backup that dies with the disk is not a backup.

### Backups

Backups go to a **different** USB, never this disk:

```bash
export CICADA_BACKUP_REPO=/run/media/cicada/YOURUSB/cicada-backup
cicada-backup init
cicada-backup seal           # put the repo key behind a passphrase
cicada-backup backup
```

`seal` matters: without it, `~/.local/share/cicada/backup.pass` sits in plaintext
in your home directory, and that one file decrypts every snapshot you have ever
taken — including the ones on a stick someone else is now holding. Sealing makes
backups interactive (age prompts on the terminal), which is the trade.

---

## 4. Duress (disk password, not a user)

You already have a user (`cicada`). Duress is **not** another account. It is a second **LUKS** passphrase at **power-on**, before anyone logs in.

```bash
sudo cicada-duress-enroll
```

Allow the zenity prompt. Type a duress passphrase (not your real one). cryptsetup then asks for the **real** LUKS passphrase to add the slot.

| At boot you type | Screen | Result |
|---|---|---|
| Real LUKS passphrase | Unlock, then `cicada` login | Normal |
| Wrong passphrase | ~12s, `Invalid passphrase` | Try again (count toward wipe) |
| **20 wrong guesses** (default) | Same wait, same text | Disk keys wiped, poweroff |
| Duress passphrase | Same wait, same text | Disk keys wiped, poweroff |

Change the cap after install: edit `CICADA_LUKS_MAX_FAIL` in `/etc/cicada/defaults.env` (or `/boot/cicada/max-fail`), then `sudo mkinitcpio -P`. Set `0` to disable. This is **boot unlock only** — wrong passwords at the lock screen do not wipe.

**Super+L (hyprlock) does not take duress.** Session lock ≠ disk. Under coercion, reboot (or wait 30 minutes locked) so you are at LUKS again.

Live USB: this command exits. Install first.

---

## 5. Work UID / Burner / camera kill

**Owner** is `cicada`. That is you. On install, firstboot creates locked `cicada-work` (second UID).

```bash
sudo passwd cicada-work            # Settings → Profiles → Set Work password
cicada-profile login work          # Work session on tty3
# Ctrl+Alt+F1 = Owner,  F3 = Work
```

Once LUKS is open, both homes sit on the same decrypted disk. That is weaker than Graphene’s per-user encryption. It still stops Work’s browser from reading Owner files in a running session.

**Burner** is a folder home for sandboxed apps (not a second UID):

```bash
cicada-profile create burner
cicada-profile switch burner
```

**Camera & microphone** (software kill — Settings → Camera & microphone):

```bash
sudo cicada-av-kill both off
sudo cicada-av-kill status
```

Blocks sandboxed apps and unloads `uvcvideo`. Not a hardware kill switch; root can reverse it.

---

## 6. If something is on fire

| Want | Do |
|---|---|
| Wi-Fi off | click WIFI → Turn Wi-Fi off |
| Lock | Super+L |
| Kill the live session now | yank the boot USB, or `sudo cicada-panic` |
| Browser broken after malloc | `sudo touch /etc/cicada/hardened-malloc-disable` and reboot |
| Wi‑Fi dead on hardened kernel | boot the default `linux` entry after install, not linux-hardened |

Web is **Helium** (official tarball, `channel/helium.lock`). Arch Chromium is not on the ISO. Unknown apps are default-deny; see `docs/PRODUCT.md`.
