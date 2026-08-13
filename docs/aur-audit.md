# AUR audit log

AUR is untrusted. No AUR package is in the ISO or security-critical path until a PKGBUILD is read and logged here.

| Date | Package | Reviewer | Why | Decision |
|---|---|---|---|---|
| 2026-08-12 | hardened_malloc | Cicada | Brief claimed extra; it is **AUR only**. | **rejected for ISO** (superseded 2026-08-13) |
| 2026-08-13 | hardened_malloc | Cicada | AUR is a thin `make` of [GrapheneOS/hardened_malloc](https://github.com/GrapheneOS/hardened_malloc). We do **not** `pacman -U` AUR. ISO Docker builder clones **tag 14** from GrapheneOS GitHub and copies `libhardened_malloc.so`. Firstboot writes `/etc/ld.so.preload` unless `/etc/cicada/hardened-malloc-disable` exists. | **upstream source, pinned tag, not AUR** |
| 2026-08-13 | helium-browser-bin | Cicada | Full Chromium fork. AUR `-bin` would fetch third-party binaries. Build-from-source is a many-hour Chromium compile. | **rejected for ISO**. Wrapper `/usr/local/bin/chromium` execs `/usr/bin/helium` if the user installed it; otherwise Arch `chromium`. |

Helium remains the intended browser. It is not on the ISO until there is a signed extra package or a Cicada-built artifact with a hash in `channel/`.
