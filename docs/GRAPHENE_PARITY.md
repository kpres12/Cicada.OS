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
- [ ] `hardened_malloc` globally (including Flatpaks) — portable, already used by secureblue
- [ ] `linux-hardened` (or equivalent patch set)
- [ ] `lockdown=confidentiality`
- [ ] Forced module signing
- [ ] Secure Boot chain (sbctl / Lanzaboote-class on supported firmware)
- [ ] Intel CET / AMD shadow stack + stronger ASLR as the MTE substitute

**Gap:** MTE has no x86 equivalent. Do not list it as done.

## 2. Attack surface reduction

Graphene: NFC/BT/UWB off by default; USB-C modes including charging-only-when-locked; new USB blocked at hardware+kernel when locked.

**Cicada:**
- [x] Wi-Fi / Bluetooth soft-blocked at boot (`cicada-radios-off`)
- [ ] USBGuard whitelist; block new enumeration when session is locked
- [ ] Optional rfkill NFC where hardware exposes it

**Gap:** almost no laptop vendor exposes Graphene-style hardware USB controller lockout. USBGuard is policy-level.

## 3. Verified boot / anti-persistence

Graphene: enhanced verified boot, signed fs-verity for app updates, hardware attestation, Auditor app.

**Cicada:**
- [ ] UEFI Secure Boot + signed UKI where firmware allows
- [ ] Measured boot / PCR sealing on TPM2 machines
- [ ] Later: a Cicada Auditor (TPM2 quotes) — we would build this, not adopt Graphene's

**Gap:** Apple EFI on the prototype MBA cannot match Pixel+Titan verified boot. Auditor-class remote attestation is the biggest true gap.

## 4. Auto reboot / duress / memory clearing

Graphene: auto-reboot after lock (10m–72h, default 18h); memory zeroed on free; duress PIN irreversible wipe, no reboot, cannot interrupt.

**Cicada:**
- [ ] systemd timer: reboot after N minutes locked
- [ ] `page_poison` / kernel zero-on-free + hardened_malloc
- [ ] LUKS duress keyslot + initramfs hook (`luksErase` / header wipe) with timing parity vs wrong PIN

## 5. Fingerprint / PIN hardening

Graphene: PIN scramble, fingerprint+PIN 2FA, 5 fingerprint attempts, 128-char passwords.

**Cicada:**
- [ ] PAM: fingerprint as second factor (`fprintd`)
- [ ] Tight attempt caps
- [ ] LUKS passphrases already unbounded (no 16-char ceiling)

## 6. Sandboxing / permissions — largest engineering piece

Graphene: per-app network permission (network-down, not crash), Sensors, Storage Scopes, Contact Scopes.

**Cicada (approximate, not equal):**
- [ ] Profile compartments (`cicada-profile`) as the UX analog of Graphene users
- [ ] Flatpak + xdg-desktop-portal for fs/camera/mic scopes
- [ ] bubblewrap / Firejail netns for per-app network kill
- [ ] AppArmor profiles per shipped app

See [docs/SANDBOX.md](docs/SANDBOX.md) for how Cicada Scopes will approximate Graphene per-app permissions (and what we will not claim).

## 7. VPN leak blocking

Graphene: DNS leak on VPN crash, multicast bypass block, no cross-profile tunnel leak.

**Cicada:**
- [ ] WireGuard + nftables kill switch (no leak window at boot)
- [ ] Drop multicast unless explicitly allowed
- [ ] Per-profile netns if/when profiles are real

## 8. Hardened browser

Graphene Vanadium: JIT off by default with per-site toggle, strict site isolation, 3P cookies off, DRM off, WebGPU off, remote services stripped.

**Cicada:**
- [ ] Helium (ungoogled-Chromium) as default when packaged
- [ ] Enterprise policy: JIT off, DRM off, WebGPU off, 3P cookies off
- [ ] Per-site JIT toggle is custom policy work, not inherited

v0 ISO ships no browser extras unless `CICADA_FULL=1` (Chromium/Firefox fallback).

## 9. Encrypted backups, logging, crash reporting

Graphene: Seedvault; user-controlled logs; memory-corruption crash detection from hardened_malloc/MTE.

**Cicada:**
- [ ] restic or borg to encrypted local/cloud
- [ ] systemd-coredump + a small hardened_malloc crash correlator
- [ ] No automatic crash upload

## Hardware tiers (repeat)

1. **Prototype — Intel MBA 2015–2017:** software privacy + hardening only
2. **Daily driver — Framework-class:** same software, better maintainability
3. **Graphene-adjacent — Librem / NitroPad + Heads/PureBoot:** boot integrity + tamper story
