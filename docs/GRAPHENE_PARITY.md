# GrapheneOS parity — laptop mapping

Source of truth: GrapheneOS features, mapped to what Cicada can actually ship on x86 laptops.
North star is Graphene *intent*. Claims stay honest about hardware.

## Scorecard

| Category | Status |
|---|---|
| Kernel/allocator hardening, radios off, VPN kill switch, browser hardening, telemetry-off, encrypted backups | Off-the-shelf — integration |
| Duress wipe, auto-reboot-to-rest, fingerprint PAM hardening | Small custom scripts |
| Per-app network/sensor permission toggles (sandbox model) | Real engineering — largest piece |
| Hardware attestation (Auditor-equivalent) | Real gap — no Titan M2 ecosystem |
| MTE-equivalent memory tagging | Hard gap — x86 silicon does not have it |

## 1. Exploit mitigations / hardened runtime

Graphene: hardened libc, hardened_malloc, ARMv9 BTI/PAC, hardware MTE in kernel allocators, forced kernel module signing, kernel lockdown, CFI.

**Cicada:**
- [ ] `hardened_malloc` globally — **AUR**, not extra; wrapper no-op until `docs/aur-audit.md`
- [x] `linux-hardened` as extra boot entry (default `linux` for MBA `broadcom-wl`)
- [x] `lockdown=confidentiality` on the hardened entry only
- [ ] Forced module signing
- [ ] Secure Boot chain (sbctl hook shipped; inert until enrolled)
- [ ] Intel CET / AMD shadow stack + stronger ASLR as the MTE substitute

**Gap:** MTE has no x86 equivalent. Do not list it as done.

## 2. Attack surface reduction

Graphene: NFC/BT/UWB off by default; USB-C modes including charging-only-when-locked; new USB blocked at hardware+kernel when locked.

**Cicada:**
- [x] Wi-Fi / Bluetooth soft-blocked at boot (`cicada-radios-off`)
- [x] USBGuard; new inserts blocked while `cicada-lock` / hyprlock runs
- [x] Randomized MAC (NetworkManager cloned-mac + iwd AddressRandomization); LLMNR/mDNS off
- [ ] Optional rfkill NFC where hardware exposes it

**Gap:** almost no laptop vendor exposes Graphene-style hardware USB controller lockout. USBGuard is policy-level.

## 3. Verified boot / anti-persistence

Graphene: enhanced verified boot, signed fs-verity for app updates, hardware attestation, Auditor app.

**Cicada:**
- [x] Device Ed25519 key + hash-chained seal log (`cicada-seal`); high-impact actions gated by `cicada-auth` ([docs/SEAL.md](SEAL.md))
- [x] `cicada-attest`: TPM2 quote if `/dev/tpmrm0` exists; otherwise export pubkey for a Pixel to pin ([docs/ATTEST.md](ATTEST.md))
- [ ] UEFI Secure Boot + signed UKI where firmware allows
- [ ] Measured boot / PCR sealing on TPM2 machines
- [ ] Later: Pixel verifies laptop `tpm2_quote` (not Graphene Auditor)

**Gap:** Apple EFI on the prototype MBA cannot match Pixel+Titan verified boot. The Pixel pin is an identity for the seal log, not a Titan substitute.

## 4. Auto reboot / duress / memory clearing

Graphene: auto-reboot after lock (10m–72h, default 18h); memory zeroed on free; duress PIN irreversible wipe, no reboot, cannot interrupt.

**Cicada:**
- [x] systemd timer: reboot after N seconds locked (default **30 min** — AFU window; `CICADA_LOCK_REBOOT_SEC`)
- [x] `init_on_free=1 init_on_alloc=1` on live boot cmdline
- [ ] LUKS duress keyslot + initramfs hook (`luksErase`) with timing parity vs wrong PIN — enroll refuses until tests exist

## 5. Fingerprint / PIN hardening

Graphene: PIN scramble, fingerprint+PIN 2FA, 5 fingerprint attempts, 128-char passwords.

**Cicada:**
- [ ] PAM: fingerprint as second factor (`fprintd`)
- [ ] Tight attempt caps
- [ ] LUKS passphrases already unbounded (no 16-char ceiling)

## 6. Sandboxing / permissions — largest engineering piece

Graphene: per-app network permission (network-down, not crash), Sensors, Storage Scopes, Contact Scopes.

**Cicada (approximate, not equal):**
- [x] `cicada-run` + MAGI scopes: Helium `NETWORK=allow` (camera/mic deny); KeePassXC `NETWORK=deny`
- [ ] Profile compartments (`cicada-profile`) as the UX analog of Graphene users
- [ ] Flatpak + xdg-desktop-portal for fs/camera/mic scopes
- [ ] AppArmor profiles per shipped app

See [docs/SANDBOX.md](docs/SANDBOX.md) for how Cicada Scopes will approximate Graphene per-app permissions (and what we will not claim).

## 7. VPN leak blocking

Graphene: DNS leak on VPN crash, multicast bypass block, no cross-profile tunnel leak.

**Cicada:**
- [x] WireGuard + nftables kill switch (`cicada-vpn on`; off is `cicada-auth` gated)
- [x] LLMNR/mDNS disabled; inbound multicast not accepted on the baseline nft table
- [ ] Kill switch loaded at boot (would black-hole first Wi-Fi — stays opt-in)
- [ ] Per-profile netns if/when profiles are real

## 8. Hardened browser

Graphene Vanadium: JIT off by default with per-site toggle, strict site isolation, 3P cookies off, DRM off, WebGPU off, remote services stripped.

**Cicada:**
- [ ] Helium (ungoogled-Chromium) as default when packaged
- [x] Managed policy: 3P cookies session-only, WebRTC non-proxied UDP off, DoH off (use resolved), Privacy Sandbox off, HTTPS-Only, DDG search
- [x] Recommended policy: JIT off, WebGPU off (user-overridable — daily-driver escape hatch)
- [ ] Per-site JIT toggle is custom policy work, not inherited

v0 ISO ships no browser extras unless `CICADA_FULL=1` (Chromium/Firefox fallback).

## 9. Encrypted backups, logging, crash reporting

Graphene: Seedvault; user-controlled logs; memory-corruption crash detection from hardened_malloc/MTE.

**Cicada:**
- [x] Hash-chained signed seal log (user-local, no upload) — [docs/SEAL.md](SEAL.md)
- [ ] restic or borg to encrypted local/cloud
- [ ] systemd-coredump + a small hardened_malloc crash correlator
- [x] No automatic crash upload

## Hardware tiers (repeat)

1. **Prototype — Intel MBA 2015–2017:** software privacy + hardening only
2. **Daily driver — Framework-class:** same software, better maintainability
3. **Graphene-adjacent — Librem / NitroPad + Heads/PureBoot:** boot integrity + tamper story
