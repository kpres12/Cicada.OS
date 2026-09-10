# Cicada — start here

You're on a **live USB**. This is a demo, not your real disk: no LUKS, nothing
persists. Reboot or unplug the stick and it's like it never happened.

## Right now

- You're `cicada`, no password. Click the dock or **SETTINGS** on the top bar.
- **WIFI** in Settings — pick a network. Telemetry stays off.
- **Web** is Helium. **Signal** and **Kleopatra** (GPG keys) are preloaded too. The launcher only shows Cicada apps, not the full Arch menu.
- Windows tile. **CLOSE** on the bar or Alt+F4. Super+V floats one window.
- Picked **Cicada.OS (copy to RAM)** at the boot menu instead of the default?
  That's amnesic mode — needs more RAM, and yanking the stick force-reboots.

## Want this as your daily OS?

Live boot has no LUKS — don't enroll duress or TPM here, it won't stick.
Installing gets you full-disk encryption, a real login, and **Duress**: a
second disk passphrase that wipes the encryption keys if you're ever forced to
type it. The full install/duress/backup walkthrough is in
`/usr/share/cicada/USER-GUIDE.txt` on this stick (`docs/USER.md` in the repo).

## If something's wrong

| Want | Do |
|---|---|
| Wi-Fi off | click WIFI → Turn Wi-Fi off |
| Lock | Super+L |
| Kill the live session now | yank the USB, or `sudo cicada-panic` |
