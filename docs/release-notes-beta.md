# Cicada.OS — public beta

**Live USB** = try and test. Session forgets on reboot.  
**Install** (`cicada-install`) = the OS. Files and wallpaper stay under LUKS.

## Highlights

- Graphene-shaped scopes + launcher monopoly (you launch Cicada, not Arch)
- Helium browser with managed hardening policy
- Work-as-UID, AFU reboot-when-locked, USB policy while locked
- Honest hardware tiers (MBA prototype ≠ Titan)

## Verify

```
shasum -a 256 -c cicada-*-x86_64.iso.sha256
```

## Flash (macOS)

```
diskutil list   # confirm the USB diskN
diskutil unmountDisk /dev/diskN
sudo dd if=./cicada-*-x86_64.iso of=/dev/rdiskN bs=4m status=progress
sync && diskutil eject /dev/diskN
```

Boot menu: **Cicada.OS** (default) or **Cicada.OS (copy to RAM)**.

Install guide: https://kpres12.github.io/Cicada.OS/install/

## Known gaps (beta)

- Hosted signed `cicada-stable` mirror not public yet
- No Graphene-class firmware story on Apple EFI
- Wallpaper / first-run polish is install-path; live remains demo
