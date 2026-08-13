# cicada-helium

Helium is the intended default browser (ungoogled-chromium lineage, like Vanadium is to Chrome).

It is **not packaged**. Helium lives on the AUR / as a source build. Cicada ISO policy: official repos only until a PKGBUILD is read and logged in `docs/aur-audit.md`.

Until then: Arch `chromium` + managed policy in `/etc/chromium/policies/managed/cicada.json` + `cicada-run org.cicada.helium`.

Do not add a Helium PKGBUILD that `makepkg`s from AUR in CI.
