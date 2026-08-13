# cicada-helium

Helium is the intended default browser (ungoogled-chromium lineage, like Vanadium is to Chrome).

**Not on the ISO.** AUR `helium-browser-bin` is third-party binaries — rejected in `docs/aur-audit.md`. Building Helium from source is a Chromium compile (hours, tens of GB).

`/usr/local/bin/chromium` already prefers, in order:

1. `/usr/bin/helium`
2. `/usr/bin/helium-browser`
3. Arch `chromium`

Install Helium yourself on an installed system; the dock Web icon keeps working. Policies in `/etc/chromium/policies/` apply to Chromium; Helium may honor a subset.
