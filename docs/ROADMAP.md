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
- [x] Firewall defaults live (nft drop). Wi-Fi available at boot; telemetry off.
- [x] OT/Eva shell readable as Cicada in first 5 seconds
- [x] Calamares or scripted install → disk (`cicada-install` LUKS2 + systemd-boot; `--internal` for non-Apple NVMe)
- [ ] Broadcom Wi‑Fi documented/working (NM picker + firmware + broadcom-wl on default `linux`)

## Phase 2 — Daily-driver alpha (2–4 weeks)

- [x] Helium as default browser + Vanadium-like enterprise policy (`channel/helium.lock`)
- [x] WireGuard + nftables kill switch (opt-in `cicada-vpn`; off until wg0.conf exists)
- [x] `linux-hardened` available after install (default live stays `linux` for MBA `broadcom-wl`). `hardened_malloc` from GrapheneOS tag 14, not AUR.
- [x] USBGuard lock-screen policy (`cicada-lock`)
- [x] Auto-reboot-when-locked timer (**30 min** default — AFU window)
- [x] Update channel sketch (`channel/` lockfile from first ISO; blob repo later)
- [x] Telemetry cut: NM connectivity off, Chromium managed policy, `docs/network-calls.md`
- [x] Seal log + `cicada-auth` gates; Pixel attest stub; Meshtastic beacon stub (`docs/SEAL.md`)

## Phase 3 — Profiles + sandbox (product identity)

- [x] `cicada-run` wraps Helium + Files + KeePassXC (real bwrap, not bind-all); default-deny
- [x] Launcher monopoly: `cicada-wofi`, dock/Waybar/MIME/desktop icons (see `docs/PRODUCT.md`)
- [x] Settings → App permissions + Profiles (Work UID / Burner)
- [x] `cicada-profile`: Work / Personal / Burner (directory homes; `--encrypt` LUKS; `--user` Unix UID)
- [x] Freeze / dispose (encrypted unmount; dispose is `cicada-auth` gated)
- [x] Settings wallpaper picker; install-only first-run wizard (public beta path)
- [ ] Signed `cicada-stable` pacman repo (lockfile + helium.lock today)
- [x] Messengers hosted, not written (`cicada-comms`): store bound into an
      encrypted profile, Flatpak floors below Flathub's, honest at-rest verdict
      (`docs/COMMS.md`, `tests/comms.sh`)

## Phase 3b — Public beta release

- [x] Site (GitHub Pages) + honest live vs install messaging
- [x] `docs/RELEASE.md` + `scripts/prepare-release.sh`
- [ ] First GitHub Release with ISO + signed sha256 (`prepare-release.sh`)
- [ ] One successful `cicada-install` smoke on spare disk (human)
- [ ] Hosted signed channel (blocks calling updates “done”)

## Phase 4 — Hard custom (ongoing)

- [x] LUKS duress keyslot + timing-padded initramfs hook (`cicada-crypt`)
- [x] TPM2 enroll helper + Pixel quote bundle (`cicada-tpm-enroll`, `cicada-attest`)
- [x] restic wrapper (`cicada-backup`)
- [x] Amnesic live USB (`docs/AMNESIC.md`)
- [x] Unified kernel images so Secure Boot covers the cmdline + initramfs, and
      PCR 11 exists to seal against (`cicada-uki`, `tests/uki.sh`)
- [x] LUKS header backup/verify/restore (`cicada-luks-header`) — the attempt cap
      and duress wipe make header damage routine, so the escape hatch is not optional
- [x] age-sealed restic repository key (`cicada-backup seal`)
- [x] Signed ISO (detached GPG over the sha256, verified in a clean keyring)
- [x] Witness beacon (`cicada-link`, `cicada-beacon`) — signed boot-chain hash
      out of band to one paired device. The only *detection* available for evil
      maid on Tier 0, where prevention is impossible (`tests/beacon.sh`)
- [ ] Beacon exercised on real hardware: Meshtastic radio, and a boot-hash
      change that is a genuine kernel upgrade rather than a fixture
- [ ] Reproducible build CI
- [ ] Immutable signed rootfs (the only thing dm-verity would add over FDE — a
      redesign, not a patch; see docs/GRAPHENE_PARITY.md)
- [ ] Tier-3 hardware docs (Librem / NitroPad / Heads)
