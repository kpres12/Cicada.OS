# The beacon

> **Evil maid is unsolved on Tier 0.** `/boot` is plaintext, unsigned and
> unmeasured; modifying the initramfs to capture the passphrase needs a
> screwdriver, not an exploit.
>
> — [README](../README.md), *What Cicada does not claim*

That is still true. On Tier 0 hardware an evil maid cannot be **prevented**,
because prevention needs a root of trust the machine does not have.

She can be **detected**. But only if the detection is reported somewhere she
does not control — a laptop that notices its own tampering and prints a warning
on its own screen has told the attacker's machine about the attacker.

So the laptop signs a short statement about itself and pushes it out of band to
one device you paired by hand. That device keeps the previous statement and
compares. This is the only part of Cicada that tells anything to anyone, and it
is worth being precise about what it is:

- It **carries no user text.** There is no message body, no address book, no
  contact list. The payload is 29 bytes of machine state and a signature.
- It **cannot receive.** Pairing is one-way by design. A witness that could send
  commands back would be a remote-administration channel on a machine whose
  entire point is that it has none.
- It **has no server and no account.** You carry a public key across the room
  once. After that there is nothing to subpoena, because there is nothing that
  knows the two devices are related except the two devices.

---

## What it actually watches

One number, mostly: **a SHA-256 over every file on the EFI system partition that
can decide what this machine boots** — the loader entries, the unified kernel
images, the fallback loaders. Path and length go into the hash alongside the
contents, so renaming or truncating a file is a change too.

Not a hash of the whole partition: the firmware writes boot counters, and a
measurement that changes on every boot is a measurement nobody reads. Not a hash
of the kernel alone either, which is the mistake Secure Boot makes without UKIs
— an initramfs is a cpio and a loader entry is a text file, and both are how an
evil maid actually gets in.

**On Tier 0 this hash is the only measurement of the boot chain that exists.**
There is no TPM, so there is no PCR; there is no Secure Boot chain the firmware
enforces. This number, held by a device the attacker did not take, is the whole
mechanism.

On Tier 1+ the beacon also carries PCR 0, 7 and 11 out of sysfs. Those are read
for reporting, not for trust — a compromised kernel can lie about them. They
matter to the witness for the same reason the ESP hash does: they are numbers
that should not change.

Alongside that it carries the seal-log sequence and tip, the hardware tier, and
twelve bits of posture (swap off, core dumps refused, syscall filter loaded,
AppArmor in the LSM stack, kill switch armed, Tor namespace up, UKI present, no
type-1 entries left, own Secure Boot keys, TPM present, LUKS root, live mode).

---

## What the witness concludes

`cicada-beacon verify` compares a statement against the last one it saw from the
same key and exits 3 if anything alarms.

| Signal | What it means |
|---|---|
| **Boot chain changed** | The ESP hash moved. Expected if you installed or rebuilt a kernel. If you did not, something rewrote your boot partition — the attack Tier 0 hardware cannot prevent. *Do not type the passphrase into that machine.* |
| **Seal log went backwards** | The sequence number dropped. An append-only log does not shrink. Someone replaced it. |
| **Duress** | A human sent `cicada-beacon` under coercion. |
| **Hardware tier dropped** | Secure Boot keys, the TPM, or the UKI is gone. |
| **Protection dropped** | Something that was on is off — kill switch, syscall filter, LSM. Reported as a note, not an alarm: these change for ordinary reasons. |
| **Silence** | Not something the laptop can send. A witness that stops hearing from a paired laptop has learned something too, and can only learn it if silence is abnormal — which is what the 6-hour timer is for. |

The witness cannot see the seal log, so it cannot tell you *why* the boot hash
moved. That correlation is yours: "did I update a kernel since yesterday?" This
is a deliberate limit. The alternative is shipping the log off the machine, and
the log is a record of what you did.

---

## Setting it up

**1. Pair, once, in the same room.**

```
cicada-link show          # fingerprint + a QR code, on this laptop
```

Read the fingerprint aloud to whoever holds the witness device, or scan the
code. Anything that carries this key over the network carries it past the
adversary the pairing exists to detect.

If the witness is another machine that can run these tools, pin it back:

```
cicada-link add pixel witness.pub
cicada-link list
```

**2. Choose how statements leave.** `/etc/cicada/beacon.conf`:

```
TRANSPORTS=meshtastic,qr
```

Tried left to right, first success wins. Nothing here reaches the network by
default:

- `meshtastic` — LoRa text via the meshtastic CLI. Works with the Wi-Fi off and
  the SIM out, which is the point. The compact statement is 124 characters and a
  Meshtastic text packet carries around 200, so it fits in one.
- `file` — appends the token to `BEACON_FILE`. Point it at a USB stick.
- `qr` — draws the token on the terminal for the witness to scan. No
  infrastructure at all; the slowest and the most reliable.
- `stdout` — for scripts and tests.

**If none of them delivers, `cicada-beacon` exits 2 and says which it tried.**
It has behaved this way since it was a stub, and the reason is that someone
under coercion will act on the belief that a duress signal went out.

**3. Turn on the boot statement.**

```
sudo systemctl enable --now cicada-beacon.timer
```

Fires 2 minutes after boot — the interesting statement is the one describing the
machine as it came up — then every 6 hours.

---

## Checking a statement

```
cicada-beacon show                      # what would be sent; sends nothing
cicada-beacon verify CIC1:...           # against the local device key
cicada-beacon verify token.txt --pub pixel.pub
```

Exit codes: `0` nothing alarming, `1` bad signature or malformed, `3` at least
one alarm.

---

## The wire format

29 bytes of body plus a 64-byte Ed25519 signature, base64url, prefixed `CIC1:`.

```
magic "C1" | ver | kind | ts(4) | seq(2) | tip[0:8] | esp_hash[0:8] | flags(2) | tier
```

The truncated digests are the reason this fits in a LoRa packet, and they are
enough: the witness is looking for *change*, and a truncated hash changes when
the full one does. The complete JSON statement goes over transports where size
is free (`cicada-beacon show`), and the compact form carries digests of exactly
the same values.

The flag bit order is frozen and append-only. A witness running an older build
must not silently reinterpret a bit.

---

## What this does not do

- **It does not prevent anything.** It is a tripwire. On Tier 2+ the boot chain
  prevents the attack and this only confirms it.
- **It does not survive a compromised kernel.** Something with code execution
  can report whatever ESP hash it likes. The beacon catches the maid who edited
  your boot partition and went away — the offline attack — not the one who is
  still resident.
- **It does not hide that a beacon was sent.** A LoRa packet is a radio
  transmission and radio transmissions have direction finders. Meshtastic is not
  a covert channel.
- **It does not know if the witness heard it.** There is no acknowledgement,
  because an acknowledgement is a receive path. Verification happens on the
  witness, by a human, deliberately.
- **It is not attestation.** No remote party is convinced of anything. One
  device you already trust is told what another device you already own claims
  about itself. See [ATTEST.md](ATTEST.md) for the TPM quote path, which is a
  different and stronger thing where the hardware supports it.
