# Cicada.OS Threat Model

## Goals

- Hostile privacy defaults (no telemetry, minimal phoning home)
- Compartmentalized profiles (Graphene-like UX; lighter than Qubes)
- Daily-driver usability with a locked, distinctive shell
- Honest security claims tied to hardware capability

## In scope (v0–v1)

- Network / telemetry abuse reduction
- Drive-by browser compromise containment (sandbox + profiles)
- Disk encryption at rest (LUKS2 Argon2id)
- Casual physical access (lock screen, USB blocked while locked, reboot-to-rest)
- User error (radios on, leaky browser defaults)
- DMA reduction (IOMMU on) and AFU window reduction (fast reboot-to-rest)

## Out of scope (for MBA-class hardware)

- Cellebrite/GrayKey-class extraction resistance equivalent to current GrapheneOS on Pixel+Titan
- Evil maid with firmware implant (no trustworthy measured boot on Apple EFI)
- PIN brute-force resistance equivalent to Titan M2 (1/day after 140)
- Cold-boot with TME/SME (Broadwell has neither)
- Intel ME neutralization guarantees
- Nation-state firmware interdiction

See [docs/ATTACKS.md](ATTACKS.md) for the forensic/laptop mapping.

## Adversaries

| Adversary | Cicada stance |
|---|---|
| Trackers / adtech | Defeat by default |
| Opportunistic malware | Mitigate via sandbox + defaults |
| Thief with powered-off laptop | LUKS; duress later |
| Evil maid | Best-effort later on Heads/PureBoot hardware only |
| Remote APTs | Reduce blast radius via profiles; not a magic shield |

## Hardware tiers

Cicada is written for a range of machines, and the security ceiling is set by
hardware, not by configuration. The software is identical across tiers; what
changes is which root of trust is available. `cicada-hw-trust` reports the tier
a given machine is actually on.

### Tier 0 — no TPM2, vendor-controlled firmware
*Apple EFI MacBooks (incl. the 2015–2017 Air), most pre-2016 x86.*

- Disk: LUKS2 + Argon2id, **passphrase is the entire boundary**
- Guessing: **not rate-limited**. An imaged disk is attacked offline forever, so
  `cicada-install` generates 80–100 bits rather than accepting a short secret
- Boot: unsigned, unmeasured. **Evil maid is undetectable** — modifying the
  plaintext ESP to capture the passphrase needs a screwdriver, not an exploit
- Optional second factor: `cicada-keyfile-enroll --and` (a USB token you can
  physically not-have)
- Honest summary: **Tails-plus-persistence.** Strong against seizure of a
  powered-off machine, DMA, and network observation. Nothing against firmware.

### Tier 1 — TPM2 present, Secure Boot not user-controlled
*Most OEM laptops with a TPM but locked-down or vendor-keyed firmware.*

- Disk: LUKS2 sealed to TPM2 PCRs 0+7 **behind a PIN** (`cicada-tpm-enroll`)
- Guessing: **rate-limited in hardware.** The TPM's dictionary-attack lockout
  counts failures in silicon and the CPU cannot reset it. This is the property
  that makes a 6-digit PIN safe on a Pixel, and it is the single largest jump
  in the whole table
- Boot: firmware replacement changes PCR 0 → unsealing fails → tamper is
  *visible* instead of silent
- Evil maid: detectable, not prevented

### Tier 2 — TPM2 + user-controlled Secure Boot
*Framework, recent ThinkPad, Star Labs, NovaCustom, System76.*

- Everything in Tier 1, plus:
- Own Secure Boot keys enrolled (`cicada-sbctl-enroll`), so the firmware refuses
  to execute anything you did not sign
- Kernel, initramfs, cmdline and os-release as one signed UKI (`cicada-uki`),
  measured into PCR 11, and the disk key sealed to 0+7+11 — a modified initramfs
  or an edited kernel command line cannot unseal the disk
- The unsigned type-1 loader entries are removed once every UKI is built *and*
  verified, so there is no second, editable way to boot the same machine
- `cicada-tpm-enroll` reads PCR 11 before including it. A UKI sitting on the ESP
  is not evidence that one booted; sealing against an all-zero PCR 11 would bind
  the disk to "booted *without* a UKI", which is the state this tier exists to
  make unbootable. `cicada-hw-trust` reports the tier on the same evidence
- **This is as close to GrapheneOS as commodity x86 gets:** a verified boot
  chain plus hardware-throttled unlock. What is still missing versus a Pixel is
  a discrete secure element holding the key material and per-app hardware
  attestation
- Evil maid: **prevented** for the boot chain, not merely detected

### Tier 3 — Tier 2 + owner-controlled boot firmware
*NitroPad / Librem with Heads or PureBoot, coreboot machines.*

- Everything in Tier 2, plus firmware you can build and measure yourself, with a
  tamper-evident boot that proves itself to you (TOTP / USB token) before you
  type anything
- Removes the "trust the vendor's firmware" assumption that Tiers 1–2 keep

### What no tier fixes
Intel ME / AMD PSP are present in all of them. Traffic analysis defeats Tor at
sufficient scale. A compromised or seized-unlocked endpoint makes every item
above irrelevant.

## Known costs of our own design choices

These are not adversary capabilities; they are prices Cicada pays for decisions
it made on purpose. They belong here so nobody rediscovers them as a surprise.

**btrfs is copy-on-write, so "deleted" is weaker than on ext4.** Overwriting a
file writes new extents and leaves the old ones unreferenced but intact until a
rebalance. Against an adversary who obtains the volume *unlocked* — a coerced
unlock, or an AFU seizure — recovering superseded file contents is materially
easier than it would be on ext4, which zeroes extent pointers on delete. We take
this for snapshots and checksums. If per-file deletion resistance matters more
to you than snapshots, ext4 is the better filesystem for this OS.

**There is no swap, and that is load-bearing.** No swapfile, no zram, no
hibernation. Swap is one of the standard forensic recoveries — key material and
plaintext paged to disk, surviving reboot, out of reach of `init_on_free`.
Adding a swapfile "for performance" would silently undo a real property.
`tests/here.sh` asserts its absence.

**Profiles share one LUKS volume.** Work/burner separation stops a running
process in one profile from reading another's files. It does nothing once the
disk is unlocked: every profile's home is plaintext on the same volume at that
point. Profiles are a blast-radius tool, not an encryption boundary.

**The ESP is plaintext.** Evil maid does not need to touch Apple EFI to win —
modifying `/boot`'s initramfs to capture the passphrase is a screwdriver-and-USB
attack with the same outcome. This is the softest of the physical-access attacks,
not the most exotic one, and it should be ranked accordingly.

*Signed and measured on Tier 1+ since the UKI work.* The kernel, initramfs,
cmdline and os-release now ship as one signed PE (`cicada-uki`), so tampering
with the initramfs or appending `init=/bin/sh` to a loader entry breaks the
signature, and systemd-stub measures the image into PCR 11 so the TPM refuses to
unseal a modified boot. Until that landed, `sbctl` signed `vmlinuz` and nothing
else — the initramfs is a cpio and a loader entry is a text file, neither of
which can carry a signature — so the boot chain was "verified" everywhere except
the two components an attacker would actually edit. **On Tier 0 (Apple EFI, no
TPM) none of this applies: there is no Secure Boot to enforce the signature and
no PCR to measure into, so the ESP remains plaintext, unsigned and unmeasured,
with no detection.**

**The LUKS attempt-cap counter lives on that same writable ESP.** An attacker who
rewrites `cicada/luks-fail.count` between power cycles gets unlimited guesses, so
`CICADA_LUKS_MAX_FAIL` is a courtesy against a shoulder-surfed short secret, not
a guarantee. There is no fix at Tier 0 — a machine with no TPM has nowhere
tamper-proof to keep a counter, and a secret baked into the initramfs is not
secret, because the initramfs ships unencrypted on the ESP (signing is not
confidentiality). What actually holds the line is elsewhere: on Tier 0 the
passphrase carries 80–100 bits by construction, so unlimited offline guessing is
already the assumed threat; on Tier 1+ the short secret is a TPM PIN and the
TPM's own dictionary-attack lockout rate-limits it in silicon — a counter the CPU
cannot reset.

**A LUKS header backup reverses the wipes.** `cicada-luks-header` exists because
the attempt cap and the duress passphrase both destroy keyslots on purpose, which
makes header damage routine here rather than exotic, and a damaged header means
permanent total data loss. But the same file undoes both wipes for whoever holds
it, and keeps working with passphrases you have since revoked. If your threat
model is coercion rather than hardware failure, the correct choice may be to have
no header backup at all. The tool states this every time rather than letting you
discover it later.

**The update channel is now the rate limiter on every CVE.** `cicada-update`
upgrades only `[cicada-stable]`, a curated snapshot, rather than Arch rolling.
That means a fix for Chromium, the kernel, systemd or glibc reaches this machine
when *Cicada* builds a snapshot, not when Arch builds the package — so a
one-maintainer channel is slower than the distribution it is based on, and far
slower than OpenBSD errata. It is the largest security regression Cicada's own
design introduces, and it is invisible from the machine unless the machine says
so, which is why `cicada-update` prints the pin's age and refuses to be quiet
about it past 30 days. Targets, the measurement, and the supported way to pull an
urgent fix straight from Arch: [SECURITY_UPDATES.md](SECURITY_UPDATES.md).

**Sandboxed apps are filtered, but they are still this user.** `cicada-run` hands
bubblewrap a seccomp program (`cicada-seccomp-gen.sh`) that denies the syscalls a
desktop app has no business making — the keyring, `userfaultfd`,
`perf_event_open`, `process_vm_readv`, `open_by_handle_at`, `pidfd_getfd` and the
rest. That closes kernel surface, which is what namespaces do not do. It does not
change the fact that an app which escapes the sandbox is running as the desktop
user, with that user's files and keys; profiles remain the blast-radius layer
above it. Compared to OpenBSD, where pledge and unveil confine essentially every
program in the base system, Cicada confines what it launches and inherits the
rest of Arch unconfined. AppArmor is in the LSM stack on installed systems
(`lsm=` on the kernel command line) but Cicada authors no profiles of its own
yet, so what it enforces is whatever upstream ships.

**`/usr` is not verity-protected, and mostly does not need to be.** Graphene
relies on dm-verity because Android's system partition is *unencrypted* and
therefore offline-modifiable. Here `/usr` lives inside the LUKS volume, so an
offline attacker cannot read or modify it at all — full-disk encryption already
covers that threat. What verity would add and FDE does not is protection against
an **online** attacker who gains root and persists in `/usr`. Closing that
requires an immutable, image-based, signed root filesystem, which is a different
operating system from a pacman-managed rolling release, not a patch to this one.

## Non-claims

Do not market Cicada on an MBA as "as secure as GrapheneOS." Market it as Graphene-*intent* with laptop-honest guarantees.
