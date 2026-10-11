# cicada-helium

Helium is the default browser (ungoogled-chromium lineage).

**On the ISO.** `scripts/install-helium.sh` downloads imputnet’s official
`x86_64_linux.tar.xz`, checks the SHA-256 in `channel/helium.lock`, and installs
to `/opt/helium`. The dock **Web** icon runs `/usr/local/bin/chromium`, which
execs Helium.

**On the channel.** `packages/cicada-helium` is a real pacman package
(Cicada-signed). Build with `CICADA_BUILD_HELIUM=1 scripts/channel-build-meta.sh`
and publish via `scripts/channel-publish-product.sh`. Class A cadence:
`scripts/check-helium-upstream.sh` + `docs/SECURITY_UPDATES.md`.

Enterprise policy (telemetry/sync/DoH off, HTTPS-only, DDG) is copied to
`/etc/chromium/policies`, `/etc/helium/policies`, and `/opt/helium/policies`.
