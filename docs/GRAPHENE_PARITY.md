# GrapheneOS parity — laptop mapping

Source of truth: GrapheneOS features, mapped to what Cicada can actually ship on x86 laptops.
North star is Graphene *intent*. Claims stay honest about hardware.

## Scorecard

| Category | Status |
|---|---|
| Kernel/allocator hardening, VPN kill switch, browser hardening, telemetry-off, encrypted backups | Off-the-shelf — integration (`hardened_malloc` from GrapheneOS tag 14; Helium official tarball) |
| Duress wipe, auto-reboot-to-rest, fingerprint PAM hardening | Small custom scripts |
| Per-app network/sensor permission toggles (sandbox model) | Real engineering — largest piece |
| Hardware attestation (Auditor-equivalent) | Real gap — no Titan M2 ecosystem |
| MTE-equivalent memory tagging | Hard gap — x86 silicon does not have it |

## 1. Exploit mitigations / hardened runtime

Graphene: hardened libc, hardened_malloc, ARMv9 BTI/PAC, hardware MTE in kernel allocators, forced kernel module signing, kernel lockdown, CFI.

**Cicada:**
- [x] `hardened_malloc` globally — GrapheneOS **tag 14** built in the ISO Docker builder (`scripts/build-hardened-malloc.sh`). Firstboot `/etc/ld.so.preload`. Opt-out: `/etc/cicada/hardened-malloc-disable`
- [x] `linux-hardened` packaged for **install** (boot entry after `cicada-install`; not on the live USB menu — MBA Broadcom + menu clutter)
- [x] `lockdown=confidentiality` on the hardened entry only
- [x] `ibt=on shstk=on` on live and installed cmdline (no-op on CPUs without CET; **not MTE**)
- [ ] Forced module signing — **won't do without forking Arch's kernel** (violates official-repos-only for security-critical packages). Policy-OS ceiling does not include a custom signed kernel.
- [ ] Secure Boot chain (sbctl hook shipped; enroll with `cicada-sbctl-enroll` in Setup Mode)

**Gap:** MTE has no x86 equivalent. CET/shadow stack is the substitute on 11th-gen Intel / Zen 3+. Do not list MTE as done.

## 2. Attack surface reduction

Graphene: NFC/BT/UWB off by default; USB-C modes including charging-only-when-locked; new USB blocked at hardware+kernel when locked.

**Cicada:**
- [ ] Wi-Fi / Bluetooth soft-blocked at boot — **dropped**. This is a laptop. `CICADA_RADIOS_OFF_DEFAULT=0`. WIFI still picks the network; telemetry stays off.
- [x] USBGuard; HID allowed (MBA keyboard/trackpad); new non-HID inserts blocked. Enabled on live + install.
- [x] Randomized MAC (NetworkManager cloned-mac); LLMNR/mDNS off
- [ ] Optional rfkill NFC where hardware exposes it

**Gap:** almost no laptop vendor exposes Graphene-style hardware USB controller lockout. USBGuard is policy-level. Live previously disabled USBGuard entirely; HID-allow rules make it safe on the Air.

## 3. Verified boot / anti-persistence

Graphene: enhanced verified boot, signed fs-verity for app updates, hardware attestation, Auditor app.

**Cicada:**
- [x] `cicada-install`: LUKS2 Argon2id + btrfs `@`/`@home` + systemd-boot (`--internal` for non-Apple NVMe)
- [x] Device Ed25519 key + hash-chained seal log (`cicada-seal`); high-impact actions gated by `cicada-auth` ([docs/SEAL.md](SEAL.md))
- [x] `cicada-attest` / `cicada-quote-verify`: TPM2 quote if `/dev/tpmrm0` exists; otherwise export pubkey for a Pixel to pin ([docs/ATTEST.md](ATTEST.md))
- [x] `cicada-tpm-enroll`: PCR 0,1,2,3,7 + passphrase fallback (exit 2 if no TPM)
- [x] `cicada-sbctl-enroll`: Setup Mode only (exit 2 on Apple EFI)
- [ ] Measured boot as default unlock (enroll is opt-in after first boot)
- [ ] Later: Pixel verifies laptop `tpm2_quote` in an app (not Graphene Auditor)

**Gap:** Apple EFI on the prototype MBA cannot match Pixel+Titan verified boot. The Pixel pin is an identity for the seal log, not a Titan substitute.

## 4. Auto reboot / duress / memory clearing

Graphene: auto-reboot after lock (10m–72h, default 18h); memory zeroed on free; duress PIN irreversible wipe, no reboot, cannot interrupt.

**Cicada:**
- [x] systemd timer: reboot after N seconds locked (default **30 min** — AFU window; `CICADA_LOCK_REBOOT_SEC`)
- [x] `init_on_free=1 init_on_alloc=1` on live **and** installed cmdline
- [x] LUKS duress keyslot + `cicada-crypt` initramfs hook: duress and wrong PIN both wait ~12s then print `Invalid passphrase`; duress then `luksErase` + poweroff. Real unlock is not padded. `cicada-duress-enroll` on the installed volume.

## 5. Fingerprint / PIN hardening

Graphene: PIN scramble, fingerprint+PIN 2FA, 5 fingerprint attempts, 128-char passwords.

**Cicada:**
- [ ] PAM: fingerprint as second factor (`fprintd`)
- [ ] Tight attempt caps
- [ ] LUKS passphrases already unbounded (no 16-char ceiling)

## 6. Sandboxing / permissions — largest engineering piece

Graphene: per-app network permission (network-down, not crash), Sensors, Storage Scopes, Contact Scopes.

**Cicada (approximate, not equal):**
- [x] `cicada-run`: bwrap is **not** bind-all; default-deny NETWORK/FILES/CAMERA/MIC/USB/SENSORS
- [x] **MIC=deny** omits PipeWire/Pulse from `XDG_RUNTIME_DIR`; **SENSORS=deny** hides hidraw/iio under `/sys`
- [x] **FILES=portal** = Downloads + app config + `GTK_USE_PORTAL=1` (storage scopes, not full `$HOME`)
- [x] **NETWORK=vpn-only** = host net only while `wg0` is up; else `--unshare-net`
- [x] System **Camera & microphone** kill (`cicada-av-kill`): unloads uvcvideo + forces MIC/CAMERA deny for sandboxed apps. Software only — not a hardware kill switch
- [x] Helium / KeePass / Files ship explicit scopes; D-Bus proxy when `xdg-dbus-proxy` exists
- [x] `cicada-profile`: Work UID auto-created on install firstboot (`create-locked`); Burner is directory HOME; `--encrypt` LUKS loop
- [ ] Flatpak FileChooser as the *only* file path for every native toolkit
- [ ] AppArmor profiles per shipped app

See [docs/SANDBOX.md](SANDBOX.md) and [docs/AMNESIC.md](AMNESIC.md) (live USB forgets; installed disk persists).

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
- [x] Helium as default browser — official `helium-linux` **0.15.4.1** tarball, sha256 in `channel/helium.lock`. Not AUR.
- [x] Managed policy: JIT off, WebGPU off, 3P cookies, WebRTC non-proxied UDP off, DoH off, Privacy Sandbox off, HTTPS-Only, DDG search (not recommended — not user-overridable via chrome://flags)
- [ ] Per-site JIT toggle is custom policy work, not inherited

See [docs/PRODUCT.md](PRODUCT.md) for launcher monopoly + default-deny.

## 9. Encrypted backups, logging, crash reporting

Graphene: Seedvault; user-controlled logs; memory-corruption crash detection from hardened_malloc/MTE.

**Cicada:**
- [x] Hash-chained signed seal log (user-local, no upload) — [docs/SEAL.md](SEAL.md)
- [x] `cicada-backup`: restic to a USB repo; password file is **not** the LUKS passphrase
- [ ] systemd-coredump + a small hardened_malloc crash correlator
- [x] No automatic crash upload

## Hardware tiers (repeat)

1. **Prototype — Intel MBA 2015–2017:** software privacy + hardening only
2. **Daily driver — Framework-class:** same software, better maintainability
3. **Graphene-adjacent — Librem / NitroPad + Heads/PureBoot:** boot integrity + tamper story
