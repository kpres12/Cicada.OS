# Cicada.OS brief

GrapheneOS philosophy, Hyprland execution. Arch engine, Cicada product layer.

Repo: `/Users/kpres12/Downloads/Cicada.OS`

This is the working spec. Cursor rules in `.cursor/rules/` are the short form. Do not rebase onto NixOS or secureblue.

## Mission

Daily-drivable Arch + Hyprland laptop OS: attack-surface reduction, exploit mitigation, privacy-by-default, scoped permissions — without making the user fight the machine. Strong defaults, explicit opt-outs, never silent failure that trains the user to disable hardening.

## Why Arch (locked)

Hyprland’s native habitat, `linux-hardened` and `hardened_malloc` in official repos, sbctl instead of Lanzaboote. What NixOS would have given (declarative proof of the closure) is approximated with `channel/` lockfiles, not a distro swap. AUR is untrusted; official repos only unless a PKGBUILD is reviewed and logged in `docs/aur-audit.md`.

## Hardware

Prototype: Intel MacBook Air 2015–2017. Graphene-class attestation / Titan-class PIN is out of scope on Apple EFI.

## GUI (current track)

Left dock, Waybar with RF state, Wofi, mako, Thunar, one-click Wi-Fi, hyprlock, coherent GTK theme. Tiling default, floating for utilities. Responsiveness over rice.

## Security tiers

See `.cursor/rules/cicada-security.mdc`. Tier 1 must pass documented tests in `docs/test-results.md` before calling this a daily driver. Tier 3 (Auditor, MTE, Android-class kernel sandbox) is a known gap — do not ship a fake version.

## Anti-goals

No security-critical AUR without audit. No fail-open crypto. No reinventing Helium/`hardened_malloc`. No feature a week of real use will force off.
