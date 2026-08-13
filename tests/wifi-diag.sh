#!/usr/bin/env bash
# Run ON THE AIR, from the Cicada terminal. Answers "why is there no Wi-Fi".
# Read-only: touches nothing, just reports. Pipe to a file and photograph it.
#   tests/wifi-diag.sh 2>&1 | tee /tmp/wifi.txt
set -uo pipefail

hdr() { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }

hdr "chip + driver binding"
# The two lines that decide everything: which Broadcom part, and who claimed it.
lspci -nnk | grep -iA3 'network\|wireless' || echo "no network-class PCI device"

hdr "modules loaded"
lsmod | grep -E '^(wl|brcmfmac|brcmsmac|bcma|ssb|b43|cfg80211|iwlwifi|ath9k) ' \
  || echo "no wireless modules loaded"

hdr "did wl refuse to load?"
modprobe -n -v wl 2>&1 | head -5
dmesg 2>/dev/null | grep -iE '\bwl\b|brcm|bcma|wlan|cfg80211' | tail -20 \
  || echo "(dmesg needs root — rerun with sudo)"

hdr "rfkill"
rfkill list

hdr "interfaces"
ip -brief link

hdr "NetworkManager view"
nmcli general status 2>/dev/null
nmcli device status 2>/dev/null
echo "-- backend actually in use --"
# If this says iwd and the driver is wl, that is the bug.
nmcli -f RUNNING,STATE general 2>/dev/null
grep -rh 'wifi.backend' /etc/NetworkManager/conf.d/ /run/NetworkManager/conf.d/ 2>/dev/null \
  || echo "wifi.backend unset (NM default = wpa_supplicant)"

hdr "supplicant / iwd presence"
for u in wpa_supplicant iwd; do
  printf '%-16s installed=%s active=%s\n' "$u" \
    "$(command -v "$u" >/dev/null && echo yes || echo NO)" \
    "$(systemctl is-active "$u.service" 2>/dev/null || echo inactive)"
done

hdr "scan attempt"
nmcli device wifi rescan 2>&1 | head -3
sleep 3
nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>&1 | head -15

hdr "last NetworkManager errors"
journalctl -b -u NetworkManager -p warning --no-pager 2>/dev/null | tail -20 \
  || echo "(journal needs root)"

printf '\n\033[1;32mdone — the first two sections are the ones that matter\033[0m\n'
