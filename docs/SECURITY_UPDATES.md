# Security updates: what the channel owes you

Cicada updates through `cicada-update`, which upgrades **only** `[cicada-stable]`
— a curated snapshot — rather than raw Arch rolling. That is a real security
decision with a real cost, and this document is the cost stated in numbers.

## The cost, plainly

On stock Arch, a Chromium or kernel fix reaches your machine as soon as the Arch
maintainers build it, usually within hours of upstream. Cicada puts a human and a
build between you and that package. **The channel is therefore the rate limiter
on every CVE in the browser, the kernel, systemd and glibc**, and a channel with
one maintainer is slower than both Arch and OpenBSD errata.

Pinning buys something in exchange: an update that has been built and booted once
before it reaches you, on an OS where a broken boot means an unbootable encrypted
disk. It is not a free win, and nothing below pretends the trade is one-sided.

## Targets

Measured from the moment a fixed package exists in Arch, not from CVE
publication — Cicada ships upstream versions and **never backports patches**, so
there is nothing to do until Arch has built it.

| Class | What it is | Target |
|---|---|---|
| **A** | Actively exploited, or remote code execution in something a scope can reach: browser, kernel, systemd, glibc, OpenSSL, bubblewrap, Tor, cryptsetup, sudo, polkit, nftables | **72 hours** to a published channel build |
| **B** | Other CVEs with a plausible path from a sandboxed app or the network | **14 days**, folded into the next snapshot |
| **C** | Everything else | next snapshot, **≤ 30 days** |

When a Class A target is going to be missed, the obligation is to say so —
a release note naming the package and the manual override below — not to let the
pin sit quietly. An advisory that arrives late still beats a machine whose owner
believes it is current.

## How you check, without trusting this file

The pin is a date, so the lag is arithmetic anyone can do:

```
cat /etc/cicada/channel      # e.g. cicada-stable-2026.08.12
```

`cicada-update` computes it for you and says it out loud: over 7 days it prints
the age with every update, over 30 days it stops and tells you the pin is very
likely missing browser and kernel fixes. Nothing here depends on you reading a
policy document — the machine reports its own staleness, on the same principle
as `cicada-status`: a protection nobody can see the state of is not a protection.

## The manual override

When a Class A fix is out and the channel has not caught up, Arch's repositories
are still configured on the machine (`[cicada-stable]` is simply listed first).
Pull the single package from Arch:

```
sudo pacman -Sy extra/chromium        # or whichever package
```

**Understand what this is.** Installing one package from a newer repository on
top of a pinned snapshot is a *partial upgrade*, which Arch does not support. For
a self-contained application it is usually fine. For anything low in the stack —
glibc, systemd, the kernel — a partial upgrade is how a machine stops booting, and
on this OS an unbootable machine means an encrypted disk you cannot reach. For
those, the supported answer is to take the whole thing and leave the pin behind:

```
sudo pacman -Syu
```

You are now on Arch rolling: faster patches, no snapshot testing, and
`cicada-update` will tell you the pin no longer describes what is installed.
That is a legitimate choice for someone who would rather have the fix today. It
should be a choice you make, not one you discover.

## What is not promised

- **No security team.** One maintainer, no rotation, no 24/7 response. A target
  is what the process aims at, not a contract, and a maintainer who is asleep or
  offline is the most likely reason a target is missed.
- **No CVE monitoring service.** Cicada tracks Arch's own security advisories and
  upstream Chromium/kernel announcements. Something that never surfaces there
  will not be caught here.
- **No backports.** Cicada never carries a patch Arch has not built. If upstream
  has not fixed it, neither has this.
- **No guarantee for AUR-sourced packages** (see [aur-audit.md](aur-audit.md)),
  which have no advisory feed at all.

This is the section that matters most when comparing Cicada to OpenBSD or
FreeBSD. Their patch process is a funded, staffed, decades-old institution with
signed errata; this one is a person and a build script. Everything Cicada does
better at rest is real, and it does not buy a single hour off the number above.
