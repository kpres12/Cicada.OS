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
4. Radios start **off** (privacy). Click **WIFI**: turn it on, pick a network, type the password. No SSID forms.
5. Windows **tile**. **CLOSE** on the bar or Alt+F4. Super+V floats one window.
6. **SETTINGS** also has sound, brightness, displays, dock position, lock, screenshot.

**Amnesic (Tails-shaped):** at the boot menu pick **Cicada.OS live (amnesic — copy to RAM)**. Needs more RAM. The stick can leave; yanking it force-reboots. Default live entry keeps the USB in (safer on 8GB Airs). Internal SSD is not mounted.

Do **not** enroll duress or TPM on the live USB. There is no LUKS yet.

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
cicada-attest                # copy ~/cicada-attest/device.pub onto a Pixel you own
```

Backups go to a **different** USB, never this disk:

```bash
export CICADA_BACKUP_REPO=/run/media/cicada/YOURUSB/cicada-backup
cicada-backup init
cicada-backup backup
```

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
| Wrong passphrase | ~12s, `Invalid passphrase` | Try again |
| Duress passphrase | Same wait, same text | Disk keys wiped, poweroff |

**Super+L (hyprlock) does not take duress.** Session lock ≠ disk. Under coercion, reboot (or wait 30 minutes locked) so you are at LUKS again.

Live USB: this command exits. Install first.

---

## 5. Extra users (Graphene-shaped)

**Owner** is `cicada`. That is you.

Add a second person (different UID, cannot sudo):

```bash
cicada-profile create work --user
# you will be asked for cicada-work's login password
cicada-profile login work          # Hyprland on tty3
# Ctrl+Alt+F1 = you,  F3 = work
```

Or reboot and log in as `cicada-work`.

Once LUKS is open, both homes sit on the same decrypted disk. That is weaker than Graphene’s per-user encryption. It still stops Work’s browser from reading Owner files in a running session.

Weaker (same person, another folder):

```bash
cicada-profile create burner
cicada-profile switch burner
```

Throwaway:

```bash
cicada-profile dispose work      # confirm dialog
```

---

## 6. If something is on fire

| Want | Do |
|---|---|
| Radios off | click WIFI → Turn Wi-Fi off, or Super+Shift+R |
| Lock | Super+L |
| Kill the live session now | yank the boot USB, or `sudo cicada-panic` |
| Browser broken after malloc | `sudo touch /etc/cicada/hardened-malloc-disable` and reboot |
| Wi‑Fi dead on hardened kernel | boot the default `linux` entry, not linux-hardened |

Helium is not on the ISO. Web is Chromium until you install Helium yourself; the dock icon will pick it up.
