# Roadmap

## Phase 0 — Scaffold (now)

- [x] Repo layout
- [x] Vendor archiso + Hyprland
- [x] releng-based ISO assemble + Docker `linux/amd64` builder
- [x] First successful `mkarchiso` build from the M2 Mac
- [x] First `cicada-stable` pin (pkglist from that ISO)
- [x] MBA live USB smoke test (Hyprland + MAGI bar on Intel Air)

## Phase 1 — Bootable v0 (1–2 weeks focused)

- [x] ISO boots on Intel MBA (EFI)
- [ ] Calamares or scripted install → external SSD
- [ ] Broadcom Wi‑Fi documented/workdiring
- [ ] Firewall + rfkill defaults live
- [ ] OT/Eva shell readable as Cicada in first 5 seconds

## Phase 2 — Daily-driver alpha (2–4 weeks)

- [ ] Helium as default browser + Vanadium-like enterprise policy
- [ ] WireGuard + nftables kill switch (multicast drop)
- [ ] `hardened_malloc` + `linux-hardened` + `lockdown=confidentiality`
- [ ] USBGuard lock-screen policy
- [ ] Auto-reboot-when-locked timer
- [x] Update channel sketch (`channel/` lockfile from first ISO; blob repo later)
- [ ] First-boot wizard (radios, VPN, profile create)

## Phase 3 — Profiles + sandbox (largest engineering)

- [ ] `cicada-profile`: Work / Personal / Burner
- [ ] Separate home + clipboard + network policy
- [ ] Per-app netns kill + Flatpak/portal scopes
- [ ] Freeze / dispose profile actions

## Phase 4 — Hard custom (ongoing)

- [ ] LUKS duress keyslot + timing-safe initramfs hook
- [ ] TPM2 lockout / PCR sealing where hardware allows
- [ ] Signed ISO + reproducible build CI
- [ ] Auditor-class TPM quotes (approximate; not Titan M2)
- [ ] Tier-3 hardware docs (Librem / NitroPad)
