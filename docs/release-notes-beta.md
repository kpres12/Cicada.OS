# Cicada.OS 2026.08.14 — public beta (first release)

**Live USB** = try and test. Session forgets on reboot.  
**Install** (`cicada-etch` / `cicada-install`) = the product. Files and wallpaper stay under LUKS.

- **Download / site:** https://kpres12.github.io/Cicada.OS/download/  
- **Install guide:** https://kpres12.github.io/Cicada.OS/install/  
- **Source:** https://github.com/kpres12/Cicada.OS  

## What’s in this build

- Cicada greeter + ASCII branding (no Arch/Hyprland in the UI)
- `cicada-session` / `cicada-login` — default desk; optional Sway/niri via Settings
- Meta/product path: dock, desktop icons, Helium, scopes, Settings
- Channel-first updates (`cicada-update` → `[cicada-stable]`, not raw Arch rolling)
- Etched default kernel: `linux-hardened` + lockdown; `linux` Wi‑Fi/Broadcom fallback
- TPM PIN unlock in `cicada-crypt` (passphrase fallback); sbctl hook for Setup Mode machines
- Settings → Security (TPM / Secure Boot / malloc / updates / VPN check)

## Get the ISO (GitHub 2 GiB asset limit)

The raw ISO is ~2.9 GiB, so this release ships **split parts**. Rebuild locally:

```bash
# download all cicada-2026.08.14-x86_64.iso.part-* assets + the .sha256
cat cicada-2026.08.14-x86_64.iso.part-* > cicada-2026.08.14-x86_64.iso
shasum -a 256 -c cicada-2026.08.14-x86_64.iso.sha256
```

## Flash (macOS)

```bash
diskutil list   # confirm the USB diskN — wrong disk wipes that drive
diskutil unmountDisk /dev/diskN
sudo dd if=./cicada-2026.08.14-x86_64.iso of=/dev/rdiskN bs=4m status=progress
sync && diskutil eject /dev/diskN
```

Boot menu: **Cicada.OS** (default) or **Cicada.OS (copy to RAM)**.

## How to test

1. Flash USB → boot on x86_64 laptop (prototype target: Intel MacBook Air 2015–2017).
2. **Live:** Wi‑Fi, Helium, Files, dock, Settings. Treat as disposable.
3. **Etch:** Desktop **Etch Cicada** → LUKS install on spare disk → reboot → greetd login → firstrun (Work / duress / TPM optional).
4. Report issues: https://github.com/kpres12/Cicada.OS/issues  

## Known gaps (beta)

- Hosted signed `cicada-stable` mirror not public yet (`cicada-update` is channel-shaped; publish pipeline is in-tree)
- No Graphene-class firmware / Secure Boot story on Apple EFI
- Live remains the demo; persistence is the install path
- Do not claim Cellebrite-matrix “no access” on MBA hardware
