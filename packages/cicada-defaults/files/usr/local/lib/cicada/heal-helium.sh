#!/usr/bin/env bash
# Repair Helium binaries that mkarchiso shipped 0644.
# Without this, /usr/local/bin/chromium finds no -x candidate and the Web icon
# does nothing — Tirimid checklist item 7 fails before the browser starts.
# Idempotent. Safe to run every boot. Root only.
set -euo pipefail
[[ ${EUID} -eq 0 ]] || exit 0
[[ -d /opt/helium ]] || exit 0

fixed=0
for name in helium chrome helium-wrapper chrome-wrapper \
            helium_crashpad_handler chrome_crashpad_handler chromedriver; do
  f="/opt/helium/${name}"
  [[ -f "${f}" && ! -L "${f}" ]] || continue
  if [[ ! -x "${f}" ]]; then
    chmod 755 "${f}" && fixed=1
  fi
done
if [[ -f /opt/helium/chrome_sandbox && ! -L /opt/helium/chrome_sandbox ]]; then
  # Nested setuid sandbox unused under --no-sandbox; never leave a setuid helper.
  chmod 755 /opt/helium/chrome_sandbox 2>/dev/null || true
fi
[[ "${fixed}" -eq 1 ]] && logger -t cicada "healed Helium exec bits under /opt/helium" 2>/dev/null || true
exit 0
