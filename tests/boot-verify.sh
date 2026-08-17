#!/usr/bin/env bash
# Run ON THE MACHINE after booting a new build. Ships as `cicada-verify`.
#
# Ordered so that a failure explains the failures below it. Time before TLS,
# TLS before DNS, DNS before Tor — because broken time looks like broken
# everything, and diagnosing upward from "the internet is down" wastes an hour.
#
# Read-only except where noted. Safe to run repeatedly.
set -uo pipefail

pass=0; fail=0; skip=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
na()   { printf '  \033[33mSKIP\033[0m %s\n' "$*"; skip=$((skip+1)); }
hdr()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

hdr "0. which build is this"
if [[ -r /usr/share/cicada/BUILD-ID ]]; then
  sed 's/^/  /' /usr/share/cicada/BUILD-ID
  ok "build stamped"
else
  no "no BUILD-ID — this image predates the build stamp, so it is older than you think"
fi

hdr "1. time (a wrong clock breaks TLS and looks like a network fault)"
if systemctl is-active chronyd >/dev/null 2>&1; then
  ok "chronyd running"
  if chronyc -n sources 2>/dev/null | grep -qE '^\^\*'; then
    ok "clock synchronised to an NTS source"
  else
    no "no synchronised source yet — TLS may fail until this settles"
    chronyc -n sources 2>/dev/null | sed 's/^/    /'
  fi
  chronyc -n authdata 2>/dev/null | grep -q 'NTS' && ok "NTS authentication active" \
    || no "sources are not NTS-authenticated"
else
  no "chronyd not running (is systemd-timesyncd still masked?)"
fi

hdr "2. network + the Wi-Fi diagnosis"
ip -brief link | sed 's/^/    /'
if ip -brief addr show | grep -qE '^(wlan|wlp)'; then
  drv="$(lspci -nnk 2>/dev/null | grep -iA3 'network' | awk -F': ' '/in use/{print $2}')"
  ok "wireless interface present (driver: ${drv:-unknown})"
else
  no "no wireless interface — run cicada-wifi-diag"
fi
grep -q 'wpa_supplicant' /etc/NetworkManager/conf.d/cicada.conf 2>/dev/null \
  && ok "NM backend is wpa_supplicant (required for broadcom-wl)" \
  || no "NM backend is not wpa_supplicant"

hdr "3. DNS"
if resolvectl query archlinux.org >/dev/null 2>&1; then
  ok "resolution works"
  resolvectl statistics 2>/dev/null | grep -i 'dnssec' | head -2 | sed 's/^/    /'
else
  no "resolution failed — captive portal? try: sudo cicada-portal on"
fi
resolvectl status 2>/dev/null | grep -q 'DNSOverTLS=opportunistic\|+DNSOverTLS' \
  && ok "DoT configured" || na "DoT state unclear"

hdr "4. hardening actually applied"
grep -q 'libhardened_malloc' /etc/ld.so.preload 2>/dev/null \
  && ok "hardened_malloc preloaded" \
  || no "hardened_malloc NOT preloaded (cicada.nomalloc set, or build skipped it)"
[[ "$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)" == 2 ]] \
  && ok "ptrace restricted" || no "ptrace_scope is not 2"
[[ "$(cat /proc/sys/fs/suid_dumpable 2>/dev/null)" == 0 ]] \
  && ok "setuid core dumps disabled" || no "suid_dumpable is not 0"
grep -q '|/bin/false' /proc/sys/kernel/core_pattern 2>/dev/null \
  && ok "core dumps refused at kernel level" || no "core_pattern still writes files"
lsmod | grep -qE '^(vivid|thunderbolt|firewire_ohci) ' \
  && no "a blacklisted module is loaded: $(lsmod | grep -E '^(vivid|thunderbolt|firewire_ohci) ' | awk '{print $1}' | tr '\n' ' ')" \
  || ok "blacklisted modules absent"
[[ -z "$(swapon --show 2>/dev/null)" ]] && ok "no swap" || no "swap is active — key material can page to disk"

# The LSM stack is a boot-time decision, not a service state. Arch's stock kernel
# compiles AppArmor in but leaves it out of the default list, so apparmor.service
# can be active, aa-status can list profiles, and nothing is enforced. Ask the
# kernel, not systemd.
if grep -qw apparmor /sys/kernel/security/lsm 2>/dev/null; then
  ok "apparmor is in the kernel LSM stack ($(cat /sys/kernel/security/lsm))"
  if command -v aa-status >/dev/null 2>&1; then
    enforced="$(aa-status --enforced 2>/dev/null || echo 0)"
    [[ "${enforced}" -gt 0 ]] && ok "${enforced} apparmor profiles in enforce mode" \
      || na "apparmor active but no profile is enforcing (nothing is confined by it)"
  fi
elif [[ -d /run/archiso ]]; then
  na "apparmor off on live by design (installed systems get lsm=...,apparmor)"
else
  no "apparmor NOT in the LSM stack — add lsm=landlock,lockdown,yama,integrity,apparmor,bpf to /etc/kernel/cmdline, then cicada-uki build"
fi

# Sandbox syscall filter. Checked by actually loading it, because the file
# existing proves only that a file exists: Seccomp: 2 inside the sandbox is the
# kernel confirming the program was accepted and is in force.
blob=/run/cicada/seccomp/default.bpf
if [[ -r "${blob}" ]]; then
  ok "seccomp program built ($(( $(stat -c %s "${blob}") / 8 )) instructions)"
  if command -v bwrap >/dev/null 2>&1; then
    mode="$(bwrap --ro-bind / / --seccomp 9 -- \
              grep -m1 '^Seccomp:' /proc/self/status 2>/dev/null 9<"${blob}" | awk '{print $2}')"
    [[ "${mode}" == 2 ]] \
      && ok "kernel accepts the program (seccomp filter mode active in a sandbox)" \
      || no "bwrap did not end up in seccomp filter mode (got '${mode:-nothing}') — scopes run unfiltered"
  fi
elif grep -qw cicada.noseccomp /proc/cmdline 2>/dev/null; then
  na "seccomp filter disabled on the kernel command line"
else
  no "no seccomp program at ${blob} — every cicada-run scope is namespaces-only (systemctl start cicada-seccomp)"
fi

# Unit confinement. CapabilityBoundingSet is the one that is trivially checkable
# and the one whose absence means "this root daemon can do anything".
for u in cicada-watchdog cicada-seccomp cicada-locked-reboot cicada-radios-off; do
  systemctl cat "${u}.service" >/dev/null 2>&1 || continue
  caps="$(systemctl show -p CapabilityBoundingSet --value "${u}.service" 2>/dev/null)"
  n_caps="$(wc -w <<<"${caps}")"
  # An unconfined root unit reports the whole set (40-odd capabilities). Each of
  # these should be at most a couple.
  if [[ "${n_caps}" -le 3 ]]; then
    ok "${u}: capabilities = ${caps:-none}"
  else
    no "${u}: ${n_caps} capabilities — the unit's hardening did not apply"
  fi
done

hdr "5. services carved out"
for u in ModemManager vboxservice vmtoolsd vmware-vmblock-fuse qemu-guest-agent \
         hv_kvp_daemon systemd-timesyncd; do
  if systemctl is-active "${u}.service" >/dev/null 2>&1; then
    no "${u} is RUNNING (should have been carved)"
  else
    ok "${u} not running"
  fi
done
systemctl is-active cicada-watchdog >/dev/null 2>&1 \
  && ok "watchdog armed" || na "watchdog inactive (no /dev/watchdog on this board?)"

hdr "6. Tor"
if systemctl is-active tor >/dev/null 2>&1; then
  ok "tor daemon running"
  if ip netns list 2>/dev/null | grep -qw onion; then
    ok "onion namespace up"
    echo "  checking real egress (30s timeout)..."
    if cicada-tor check 2>&1 | grep -q 'exits via Tor'; then
      ok "traffic from the namespace genuinely exits via Tor"
    else
      no "onion namespace is up but traffic is NOT confirmed through Tor"
    fi
  else
    no "onion namespace down: sudo systemctl start cicada-tor-netns"
  fi
else
  no "tor not running"
fi

hdr "7. seal log"
cicada-logs --verify >/dev/null 2>&1 && ok "seal chain intact" || no "seal chain broken or uninitialised"

hdr "8. browser"
# The Web icon launches /usr/local/bin/chromium, which picks the first
# EXECUTABLE candidate. mkarchiso copies the profile airootfs with
# --no-preserve=mode, so anything outside profiledef.sh's file_permissions
# arrives 0644 — a browser that is fully installed and cannot be started, and
# from a desktop click the failure is completely silent. Check the bit, not
# just the path.
if [[ -e /opt/helium/helium || -e /opt/helium/chrome ]]; then
  helium_bin="$(readlink -f /opt/helium/chrome 2>/dev/null)"
  [[ -f "${helium_bin}" ]] || helium_bin=/opt/helium/helium
  if [[ -x "${helium_bin}" ]]; then
    ok "Helium binary executable ($(cat /etc/cicada/helium.version 2>/dev/null || echo version-unknown))"
  else
    no "Helium is installed but NOT executable ($(stat -c %A "${helium_bin}" 2>/dev/null)) — the Web icon will do nothing"
  fi
  for extra in /opt/helium/helium-wrapper /opt/helium/helium_crashpad_handler; do
    [[ -e "${extra}" ]] || continue
    [[ -x "${extra}" ]] && ok "$(basename "${extra}") executable" \
      || no "$(basename "${extra}") is not executable"
  done
else
  no "no Helium at /opt/helium — install-helium.sh did not run for this build"
fi
[[ -x /usr/local/bin/cicada-wifi-diag ]] && ok "cicada-wifi-diag executable" \
  || no "cicada-wifi-diag is not executable — run it with: bash /usr/local/bin/cicada-wifi-diag"

hdr "9. things only you can check"
cat <<'EOF'
    - Lock (Super+L). Type a WRONG passphrase: it must say DENIED, not freeze.
      Then unlock. Plug in a USB device AFTER unlocking; it should enumerate.
    - Close the lid for ~3 minutes. It must lock, stay awake, then reboot to a
      passphrase prompt (BFU). If it suspends instead, sleep.conf did not apply.
    - cicada-run org.torproject.torbrowser  — should open through Tor.
EOF

printf '\n\033[1m%d passed, %d failed, %d skipped\033[0m\n' "${pass}" "${fail}" "${skip}"
[[ "${fail}" -eq 0 ]] || {
  echo "Fix failures top-down: a wrong clock or dead DNS makes everything below it lie."
  exit 1
}
