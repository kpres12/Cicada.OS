# Cicada.OS

Arch-based privacy/security laptop OS. GrapheneOS *intent*, Hyprland daily-driver
feel, Helium as the browser.

**Public beta (2026.08.14):** [Download ISO](https://github.com/kpres12/Cicada.OS/releases/latest) · [Site](https://kpres12.github.io/Cicada.OS/) · [Install](https://kpres12.github.io/Cicada.OS/install/)

**Site:** [`site/`](site/) — download / install / features (GitHub Pages).  
**North star:** hostile defaults and profile isolation on laptops — honest about
hardware limits.
**Method:** Arch is the engine. Cicada owns defaults, release channel, shell,
and profiles.

**The one-line summary:** *hostile defaults on a laptop that may not be able to
attest.* How much of GrapheneOS you actually get is set by your hardware, not by
this configuration — see [Hardware tiers](#hardware-tiers).

---

## Design rule

Everything here follows one rule, and most of the bugs found so far were
violations of it:

> **Fail closed on anything that would leak a secret. Degrade *visibly* on
> anything that only reduces protection.**

Knowing the time leaks nothing, so a network that blocks authenticated NTP gets
you unauthenticated time and a yellow line in `cicada-status` — not a laptop
that cannot validate a certificate. A VPN kill switch, by contrast, tears the
tunnel down rather than let one packet out.

A protection users switch off protects nobody. Defaults are chosen to survive
contact with campus Wi-Fi.

---

## Hardware tiers

The software is identical across tiers. What changes is which root of trust
exists. `cicada-hw-trust` reports the tier a machine is actually on.

| Tier | Hardware | Unlock secret | Evil maid |
|---|---|---|---|
| **0** | Apple EFI Macs, pre-2016 x86 | 80–100 bit passphrase, **no rate limiting** | **undetectable** |
| **1** | TPM2, vendor Secure Boot | short PIN, **throttled in hardware** | detectable |
| **2** | TPM2 + your own SB keys + signed UKI | short PIN + PCR 0+7+11 | **prevented** (boot chain) |
| **3** | + Heads / PureBoot / coreboot | same, on firmware you can build | vendor trust removed |

The inversion is the important part. On **Tier 0** the passphrase must be long
because nothing can rate-limit an offline attack on a disk image. On **Tier 1+**
the TPM checks the PIN itself and its dictionary-attack lockout counts failures
in silicon, so a short PIN is genuinely safe — the same property that makes a
6-digit PIN safe on a Pixel.

Tier 2 is as close to GrapheneOS as commodity x86 gets. Still missing versus a
Pixel: a discrete secure element holding key material, and per-app hardware
attestation.

Full detail: [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md).

---

## What it does

**Disk & memory**
- LUKS2 + Argon2id, memory cost scaled to the machine (¼ RAM, capped 1 GiB)
- `cicada-install` **generates** an 80/100-bit passphrase rather than accepting a
  short one; self-chosen needs 6+ words or 24+ chars
- TPM2 sealing **behind a PIN** (`cicada-tpm-enroll`) — never PIN-less, which
  would make the disk unlock itself on power-on
- USB unlock token as a second factor (`cicada-keyfile-enroll`), `--and` mode
  requires two tokens so a lost stick cannot destroy the disk
- LUKS header backup/verify/restore (`cicada-luks-header`) — refuses to write to
  the disk it protects, and says out loud that the backup also undoes the duress
  and attempt-cap wipes
- No disk swap ever; **zram** (RAM-only, no writeback) for memory relief
- Core dumps refused at both systemd and kernel level
- `noatime`, free-RAM scrub at shutdown

**Boot chain**
- **Unified kernel images** (`cicada-uki`) — kernel, initramfs, cmdline and
  os-release in one signed PE. Without this, Secure Boot signs `vmlinuz` and
  nothing else: an initramfs is a cpio and a loader entry is a text file, so an
  evil maid edits `options … init=/bin/sh` on the plaintext ESP and the firmware
  boots it, having verified only the component nobody needed to touch
- That is also what creates **PCR 11**, so `cicada-tpm-enroll --pcrs 0+7+11`
  binds the disk key to this exact kernel+initramfs+cmdline
- Type-1 entries are removed only after every UKI is built *and* verified to be
  a real PE carrying `.linux`/`.initrd`/`.cmdline`; `cicada-uki restore` reverses it
- Your own Secure Boot keys via `cicada-sbctl-enroll`; kernel upgrades rebuild
  and re-sign the UKI through a pacman hook
- Releases are **GPG-signed** — a published sha256 authenticates nothing, since
  whoever can swap the ISO can swap the hash beside it

**Anti-forensics** (mapped against *The Law Enforcement and Forensic Examiner's
Introduction to Linux*, which is the actual playbook)
- Shell history to `/dev/null`, journal `Storage=volatile`
- Thumbnail cache and `recently-used.xbel` wiped at boot
- Amnesic live mode: overlay in RAM, USB yank triggers panic reboot

**AFU / seizure**
- Suspend and hibernation disabled — a suspended laptop holds the volume key in
  DRAM indefinitely
- Lid close locks immediately; BFU reboot after 20 min closed, 30 min open
- **Hardware watchdog** enforces that window even if userspace is compromised;
  a systemd timer cannot survive an attacker with code execution
- USB `authorized_default=0` while locked — the *kernel* refusing new devices,
  not userspace policy. Already-authorized devices keep working, so the built-in
  keyboard survives
- Duress credential at **both** the LUKS prompt and the lock screen — coercion
  usually happens to a machine that is already running

**Network**
- nftables default-deny inbound; VPN kill switch with no `ct established`
  exemption in the output chain
- MAC randomization, and DHCP hostname/client-id/DUID withheld so a stable
  identifier does not undo it
- Quad9 DoT system-wide + DoH in the browser, with ECH; degrades DoH→DoT→plain
- **Tor as a first-class `cicada-run` scope** — a network namespace whose only
  route is Tor, enforced by the kernel, not by a proxy setting an app can ignore
- chrony with NTS from three jurisdictions

**Sandboxing**
- `cicada-run` default-denies network, files, camera, mic, USB, sensors
- bubblewrap + `xdg-dbus-proxy`, per-app scopes
- **A seccomp filter, not just namespaces.** bubblewrap installs no syscall
  filter unless handed one, and a namespace hides resources without shrinking
  the kernel API behind them. `cicada-seccomp-gen.sh` builds the program at boot
  from the running kernel's own syscall table — keyring, `userfaultfd`,
  `perf_event_open`, `process_vm_readv`, `open_by_handle_at`, `pidfd_getfd` and
  the rest denied with EPERM, never a kill
- `--new-session` (no TIOCSTI back into the launching terminal) and
  `--unshare-ipc` (no SysV shared memory between scopes)
- hardened_malloc preloaded, `linux-hardened` available as a boot entry
- Browser policy is **managed** (non-overridable): JIT off, WebGPU off, site
  isolation, post-quantum key agreement

**Tamper evidence**
- Prevention needs a root of trust; **detection** only needs somewhere the
  attacker does not control. `cicada-beacon` signs a hash over every file on
  the EFI system partition that decides what the machine boots and pushes it to
  one device paired by hand (`cicada-link`) — over LoRa, a USB stick, or a QR
  code on the screen. On Tier 0, where `/boot` is plaintext and unmeasured,
  **this is the only measurement of the boot chain that exists**
- The witness compares against the last statement it saw: a boot hash that moved
  on a boot with no kernel upgrade, a seal log whose sequence went *backwards*,
  a hardware tier that dropped. It carries no messages, has no account or
  server, and cannot receive — a witness that could talk back would be a
  remote-administration channel on a machine designed to have none
- No transport delivered it → **exit 2**, never a fake success. Someone under
  coercion acts on the belief that the signal went out

**Messaging**
- Cicada does not ship a messenger, and will not: the hard parts of Signal are
  the network and the metadata, not the ratchet, and Matrix's exposure is in the
  federation design rather than in any client
- What it does instead is host one honestly. `cicada-comms bind` moves a
  message store into an encrypted profile, so `cicada-lock` freezing that
  profile puts the history at rest — the thing Electron's `safeStorage` cannot
  do for itself on a session with no keyring, where it falls back to a constant
  key compiled into the binary
- `cicada-comms doctor` reports which of those is true on *your* machine.
  `shred` erases LUKS keyslots when it can and says plainly that it was only an
  unlink when it cannot

**Attack surface**
- archiso's installer-ISO services carved out: hypervisor guest agents
  (a host→guest control channel by design), cloud-init, ModemManager,
  mirror fetch, pcscd
- 8 setuid binaries stripped, re-applied by a pacman hook after every upgrade
- `vivid` (CVE-2019-18683) and unused filesystem parsers blacklisted
- **Cicada's own root daemons are confined**: every unit runs with
  `NoNewPrivileges`, a named capability set (the watchdog holds `CAP_SYS_BOOT`
  and nothing else; the filter generator holds none), and a syscall filter where
  one cannot silently break an emergency path. The exceptions are written down
  in the units themselves with the reason
- AppArmor is put **in the kernel's LSM stack** (`lsm=` on the command line).
  Arch's stock kernel compiles it in but leaves it out of the default list, so
  enabling the service alone yields an LSM that enforces nothing

---

## Tools

| Command | Does |
|---|---|
| `cicada-status` | The posture **in force** — time, DNS, MAC, VPN, Tor, swap, core dumps |
| `cicada-verify` | Full boot checklist, ordered so failures explain the ones below |
| `cicada-hw-trust` | Which tier this machine is on, and the next command to climb one |
| `cicada-tor` | `status` / `check` / `bridges` / `limits` |
| `cicada-portal` | Time-boxed plaintext DNS for a captive portal; self-reverting |
| `cicada-logs` | Seal log + journal; `--verify` checks the chain |
| `cicada-run` | Launch an app in its scope |
| `cicada-profile` | Work / Personal / Burner compartments; `end` puts one back at rest |
| `cicada-firstrun` | One-time wizard: TPM PIN on Tier 1+, USB token on Tier 0 |
| `cicada-wifi-diag` | Why there is no Wi-Fi |
| `cicada-link` | Pair the one device that witnesses this laptop |
| `cicada-beacon` | Signed boot-chain statement out of band; `verify` on the witness |
| `cicada-comms` | Where a messenger's history lives, and what that is worth |

Escape hatches, typed at the boot menu (`e` on the entry):
`cicada.nomalloc` disables hardened_malloc; `cicada.nowatchdog` disables the
watchdog. Every control that can render the machine unusable has one.

---

## Build

On Apple Silicon this cross-builds an **Intel/x86_64** image:

```bash
./scripts/build-iso-docker.sh     # → out/cicada-*.iso
```

Then flash, boot the Mac with `Option`, and install to an **external SSD** first.
Details in [docs/BUILD.md](docs/BUILD.md) and [docs/INSTALL.md](docs/INSTALL.md).

Every ISO carries `/usr/share/cicada/BUILD-ID` with the commit and whether the
tree was dirty. Check it against `git rev-parse --short HEAD` before concluding
anything from a test — a stale ISO is how a fixed bug gets re-reported.

## Tests

```bash
tests/preflight.sh   # syntax, seal chain, assemble
tests/here.sh        # ~90 checks: defaults, fail-closed CLIs, boot entries
tests/seam.sh        # live vs installed parity — where most bugs have lived
tests/seal.sh        # hash chain + tamper detection
tests/seccomp.sh     # decodes and simulates the sandbox syscall filter
tests/beacon.sh      # signs a statement, edits a fake ESP, requires the alarm
tests/comms.sh       # the at-rest verdict, and everything cicada-comms refuses
tests/afu.sh         # USB gate, gate restore, watchdog arming, escape hatches
tests/linux.sh       # needs Docker: real kernel — nftables, NTS, Tor, duress
tests/boot-verify.sh # run ON the machine after booting (ships as cicada-verify)
```

These are largely structural — they prove a config *says* a thing. They do not
prove the kernel accepts it. A clean run is necessary, not sufficient; the last
build shipped a broken pacman hook that all four suites passed. `seccomp.sh` is
the exception worth copying: it decodes the emitted BPF program and runs the same
instruction machine the kernel does, so it fails on a wrong verdict rather than a
missing string. `boot-verify.sh` then loads the program for real.

---

## Status

**Pre-alpha.** Boots to a Hyprland desktop on an Intel MacBook Air. Much of the
hardening above is verified structurally and by loading rulesets on real
kernels, but has **not** been exercised on hardware end to end.

**Known-unverified, and why.** Two lists, because "unverified" was covering two
different things and that hid real bugs.

*Still needs the Air, cannot be reproduced anywhere else:* hardened_malloc
running under Helium, whether a chipset watchdog resets this board, whether the
kernel refuses a USB device at `authorized_default=0`, and whether a LoRa radio
carries a beacon.

*Verified on a real Linux kernel* (`tests/linux.sh`, a privileged `linux/amd64`
container): the baseline firewall and the VPN kill switch load and the kernel
reports the policies claimed here; an established TCP flow **stops** the moment
the switch arms, which is the `ct established` claim above tested with packets
instead of grep; chrony's shipped config completes NTS-KE with all three
operators; Tor reaches `Bootstrapped 100%`; the onion namespace has one route
and no physical interface.

*Verified in simulation* (`tests/afu.sh`, `tests/beacon.sh`): the USB gate, the
gate's restore path, watchdog arming, the escape hatches, and the beacon's
signing, wire format and alarm.

Splitting that list is not bookkeeping — it found five defects, none of which
needed hardware to expose. **The session duress credential had never worked at
all**: `pam_exec` writes the password without a trailing newline, so `read`
returned non-zero, and the hook exited before it ever computed a hash. Also: the
USB gate reported success when it had written nothing; `cicada-lock` stranded
the gate closed if it was killed rather than exiting normally; `cicada.nomalloc`
could not rescue a machine that was already broken; and the beacon's Meshtastic
call could hang forever on the duress path.

A clean run is still necessary, not sufficient.

Do not rely on this for anything that matters yet. See
[docs/ROADMAP.md](docs/ROADMAP.md) and [docs/test-results.md](docs/test-results.md).

## What Cicada does not claim

- **It is not GrapheneOS**, and on Tier 0 hardware it cannot approach it. No
  secure element, no verified boot, no key-guessing rate limit.
- **Evil maid is unprevented on Tier 0.** `/boot` is plaintext, unsigned and
  unmeasured; modifying the initramfs to capture the passphrase needs a
  screwdriver, not an exploit. `cicada-beacon` makes it *detectable* by a device
  the attacker does not hold, which is a different and weaker claim: it tells
  you afterwards, and only if you paired a witness and read what it says.
- **Intel ME / AMD PSP** are present on every tier and are not neutralized.
- **Tor does not hide that you use Tor** without a pluggable transport, and
  obfs4/snowflake are AUR-only — on a censored network use Tor Browser, which
  bundles its own.
- **Messengers are confined by Flatpak, not by Cicada.** Signal, SimpleX and
  Element run under Flatpak's sandbox with floors written below Flathub's
  defaults — not under a `cicada-run` scope, and not under the syscall filter
  above. That boundary is deliberate and permanent, not a gap
  ([docs/COMMS.md](docs/COMMS.md)). What Cicada contributes is where the message
  store lives and what it is worth at rest.
- **A seized-unlocked or compromised machine** makes everything above moot.

Threat model: [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) ·
[docs/ATTACKS.md](docs/ATTACKS.md) ·
[docs/GRAPHENE_PARITY.md](docs/GRAPHENE_PARITY.md) ·
[docs/SANDBOX.md](docs/SANDBOX.md) · [docs/DESIGN.md](docs/DESIGN.md) ·
[docs/BEACON.md](docs/BEACON.md) · [docs/COMMS.md](docs/COMMS.md)
