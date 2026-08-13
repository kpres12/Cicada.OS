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
- [x] Firewall + rfkill defaults live
- [x] OT/Eva shell readable as Cicada in first 5 seconds
- [x] Calamares or scripted install → disk (`cicada-install` LUKS2 + systemd-boot; `--internal` for non-Apple NVMe)
- [ ] Broadcom Wi‑Fi documented/working (NM picker + firmware + broadcom-wl on default `linux`)

## Phase 2 — Daily-driver alpha (2–4 weeks)

- [ ] Helium as default browser + Vanadium-like enterprise policy
- [x] WireGuard + nftables kill switch (opt-in `cicada-vpn`; off until wg0.conf exists)
- [x] `linux-hardened` extra boot entry (default `linux` for MBA `broadcom-wl`). `hardened_malloc` is AUR — not on ISO; see `docs/aur-audit.md`
- [x] USBGuard lock-screen policy (`cicada-lock`)
- [x] Auto-reboot-when-locked timer (**30 min** default — AFU window)
- [x] Update channel sketch (`channel/` lockfile from first ISO; blob repo later)
- [x] Telemetry cut: NM connectivity off, Chromium managed policy, `docs/network-calls.md`
- [x] Seal log + `cicada-auth` gates; Pixel attest stub; Meshtastic beacon stub (`docs/SEAL.md`)

## Phase 3 — Profiles + sandbox (largest engineering)

- [x] `cicada-run` wraps Helium + KeePassXC (real bwrap, not bind-all)
- [x] `cicada-profile`: Work / Personal / Burner (directory homes; `--encrypt` LUKS; `--user` Unix UID)
- [x] Freeze / dispose (encrypted unmount; dispose is `cicada-auth` gated)

## Phase 4 — Hard custom (ongoing)

- [x] LUKS duress keyslot + timing-padded initramfs hook (`cicada-crypt`)
- [x] TPM2 enroll helper + Pixel quote bundle (`cicada-tpm-enroll`, `cicada-attest`)
- [x] restic wrapper (`cicada-backup`)
- [x] Amnesic live USB (`docs/AMNESIC.md`)
- [ ] Signed ISO + reproducible build CI
- [ ] Tier-3 hardware docs (Librem / NitroPad / Heads)
