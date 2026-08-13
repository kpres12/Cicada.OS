# AUR audit log

AUR is untrusted. No AUR package is in the ISO or security-critical path until a PKGBUILD is read and logged here.

| Date | Package | Reviewer | Why | Decision |
|---|---|---|---|---|
| 2026-08-12 | hardened_malloc | Cicada | Brief claimed extra; it is **AUR only**. | **rejected for ISO** (superseded 2026-08-13) |
| 2026-08-13 | hardened_malloc | Cicada | AUR is a thin `make` of [GrapheneOS/hardened_malloc](https://github.com/GrapheneOS/hardened_malloc). We do **not** `pacman -U` AUR. ISO Docker builder clones **tag 14** from GrapheneOS GitHub and copies `libhardened_malloc.so`. Firstboot writes `/etc/ld.so.preload` unless `/etc/cicada/hardened-malloc-disable` exists. | **upstream source, pinned tag, not AUR** |
| 2026-08-13 | helium-browser-bin | Cicada | Full Chromium fork. AUR `-bin` would fetch third-party binaries. Build-from-source is a many-hour Chromium compile. | **rejected for ISO** (superseded same day) |
| 2026-08-13 | Helium (official tarball) | Cicada | [imputnet/helium-linux 0.15.4.1](https://github.com/imputnet/helium-linux/releases/tag/0.15.4.1) `x86_64_linux.tar.xz`. SHA-256 pinned in `channel/helium.lock`. ISO builder downloads, verifies, installs to `/opt/helium`. Not AUR. | **upstream tarball, pinned hash, not AUR** |

Helium is the default browser on the ISO. Arch `chromium` is not shipped. Runtime libs (`nss`, `gtk3`, …) come from extra.
