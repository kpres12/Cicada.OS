# Messaging

Cicada does not ship a messenger, and the decision not to is the design.

The hard parts of Signal are not the ratchet. They are sealed sender, private
contact discovery, a network the people you talk to are already on, and a decade
of client bugs found by other people. The hard part of Matrix's metadata problem
is that it is the federation design and not a defect: every homeserver with a
member in a room replicates that room's membership, device list and timestamps,
and keeps them. You do not fix that with a better client.

A pre-alpha OS maintained by one person writing a new end-to-end encrypted
protocol would be the first entry in ["What Cicada does not claim"](../README.md)
that deserved to be there and was not.

So the claim here is narrower and it is true: **Cicada is a better host for a
messenger than the messenger can ask its own platform to be.** Same protocols,
same clients, different machine underneath.

---

## The gap this closes

Signal Desktop and Element have weaknesses that are not fixable in the app and
are fixable in the OS.

**The database key.** Electron wraps an app's database key with `safeStorage`.
On Linux that means the Secret Service — gnome-keyring or kwallet — when one
answers on the session bus, and when none does, Electron falls back to what it
calls *basic text*: AES under a constant key compiled into the binary. That is
not a weaker secret, it is a published one, so the wrapped key sitting beside
the database it protects is decorative. Cicada is a Hyprland session with no
keyring daemon by default, which means this is the case here unless you install
one. `cicada-comms doctor` reports which of the two is actually true on your
machine rather than which one the release notes describe.

The app cannot fix this. The host can, by making the store's protection be the
volume it sits on rather than a key file sitting next to it.

**Where the store lives.** By default a Flatpak messenger's history lands in
`~/.var/app/<id>` in your real home, where full-disk encryption is the only
thing protecting it — that is, nothing at all on a laptop that is already
unlocked, which is the state a laptop is in when it is seized. `cicada-comms
bind` moves the store into an encrypted `cicada-profile` and leaves a symlink
behind. Two things follow:

- `cicada-profile freeze` takes that profile's volume key out of RAM. `cicada-lock`
  already does this for every non-active profile when the screen locks, so
  locking the laptop now puts the message history at rest.
- A frozen profile means the messenger will not start. That is the protection
  working. It is written down here because it will otherwise be reported as a
  bug.

**Destroying it.** `cicada-comms shred` erases the LUKS keyslots of the profile
holding the store — the only erase on flash that is actually an erase, because
overwriting a file leaves whatever the controller decided to keep. When the
store is *not* in an encrypted profile, `shred` unlinks it and says plainly that
this is not the same thing. It does not print a success it did not earn.

**A linked desktop is a full copy.** Linking Signal Desktop puts your entire
history on a machine with no secure element, no hardware key-guessing rate
limit, and — on Tier 0 — no verified boot. The phone throttles a PIN in
silicon. Whether anything on this laptop does is decided by
[Hardware tiers](../README.md#hardware-tiers), not by this page.

---

## What sandbox is actually in force

None of Signal, SimpleX or Element has an official Arch package, and the AUR is
out of scope ([aur-audit.md](aur-audit.md)). So on Cicada they are Flatpaks, and
a Flatpak app runs under Flatpak's own bwrap — **not** under a `cicada-run`
scope. Nesting one inside the other is two sandboxes fighting over user
namespaces to produce a window that does not open, and an isolation feature
people turn off is an isolation feature that protects nobody.

What Cicada does instead is tighten the Flatpak sandbox below what Flathub
ships. `cicada-pkg` applies these at install time, and `cicada-comms harden`
re-applies them — worth doing after an update, because a Flatpak update can
reset an app's permissions to whatever its new manifest asks for. They are
written at `--system` level, behind root, for the reason `cicada-scopes` gives
about its own floors: a `--user` override can grant back what a `--user`
override took away, so a floor written at user level is not a floor.

| Override | Why |
|---|---|
| `--nofilesystem=home` | Flathub grants broad host filesystem access so attachments "just work". It also means one renderer bug reads every document in the profile. |
| `--filesystem=xdg-download` | Attachments still land somewhere. Downloads and nothing else. |
| `--nosocket=x11 --nosocket=fallback-x11` | Cicada is Wayland-only, so nothing needs it, and an app holding the X socket reads every keystroke sent to every other X client. |
| `--nodevice=all --device=dri` | Camera and microphone through the portal — a prompt — instead of by standing grant. |

Flatpak does install a seccomp filter of its own, so the honest statement is
"Flatpak's syscall filter, not Cicada's", not "no filter". `cicada-comms status`
says which regime an app is under.

`cicada-run` scopes for all three ship anyway
(`/usr/share/cicada/scopes/org.signal.Signal.env` and friends) because a native
install is possible and because the floor should exist before someone needs it.
Those scopes are `FILES=portal`: the home the app sees is a tmpfs with exactly
one directory bound back, and no `~/.cache` bind — an Electron cache that
outlives the process is a copy of decrypted message content in a directory
nobody thinks of as the message store.

One detail worth keeping: Signal and Element are Electron, which is Chromium,
which means they need `UNSHARE_PID=0` in `cicada-run` for the same reason Helium
does. With the PID namespace unshared the zygote cannot fork and the window
comes up blank.

---

## Choosing between them

**SimpleX** has no user identifier at all — no phone number, no username, no
account for a server to be asked about. That is a strictly better metadata story
than Signal's phone numbers and a categorically better one than Matrix. It is
the closest thing to "Signal, but better" that exists as shipping software, and
Cicada packages it rather than competing with it.

**Signal** has the network. Sealed sender and private contact discovery are real
work that nobody else has matched. If the people you need to reach are on
Signal, the metadata argument does not get to override that.

**Element / Matrix** is here as a floor, not a recommendation. Read the second
paragraph of this page before choosing it for anything that matters.

**Briar** is not packaged and is worth reading anyway: Tor plus local mesh, no
infrastructure, designed for the disconnected adversarial case. It overlaps with
[the beacon](BEACON.md) in spirit — the difference is that the beacon is not
trying to be a messenger.

---

## Commands

```
cicada-comms status              posture per messenger, as enforced
cicada-comms doctor [app]        why a store is rated the way it is
cicada-comms harden [app]        re-apply the Flatpak sandbox floors
cicada-comms bind <app> <prof>   move the store into an encrypted profile
cicada-comms unbind <app>        move it back
cicada-comms shred <app|--all>   destroy it (prints what it could not guarantee)
```

`shred` is gated by `cicada-auth confirm comms.shred` and lands in the seal log.
The `--duress` form skips the prompt, for the same reason `cicada-beacon` is
never gated: coercion has to be fast.

A typical setup:

```
sudo cicada-profile create chat --encrypt
cicada-pkg                       # install Signal / SimpleX
cicada-comms bind signal chat
cicada-comms status
```

---

## What this does not do

- **It does not protect a running session.** A compromised or seized-unlocked
  laptop has the store decrypted and mounted. Everything above is about at-rest.
- **It does not touch the server side.** Anything already synced is already
  synced; `shred` destroys the local copy and nothing else.
- **It does not make Matrix private.** See above. A sandbox cannot fix a
  protocol.
- **It does not audit the clients.** Signal Desktop and Element are large
  Electron applications and Cicada has read neither.
