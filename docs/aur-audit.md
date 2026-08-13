# AUR audit log

AUR is untrusted. No AUR package is in the ISO or security-critical path until a PKGBUILD is read and logged here.

| Date | Package | Reviewer | Why | Decision |
|---|---|---|---|---|
| 2026-08-12 | hardened_malloc | Cicada | Brief claimed extra; it is **AUR only**. ISO must not pull AUR. Wrapper `/usr/local/bin/chromium` will preload it *if* installed later. | **rejected for ISO** |

Helium (Tier 2 default browser) will land here before it is packaged. Until then Chromium from extra is the browser, wrapped with `hardened_malloc` via `/usr/local/bin/chromium`.
