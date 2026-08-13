# cicada-helium

Helium is the default browser (ungoogled-chromium lineage, like Vanadium is to Chrome).

**On the ISO.** Not AUR. The Docker builder downloads imputnet’s official `x86_64_linux.tar.xz`, checks the SHA-256 in `channel/helium.lock`, and installs it to `/opt/helium`. The dock **Web** icon runs `/usr/local/bin/chromium`, which execs Helium.

Enterprise policy (telemetry/sync/DoH off, HTTPS-only, DDG) is copied to `/etc/chromium/policies`, `/etc/helium/policies`, and `/opt/helium/policies`.
