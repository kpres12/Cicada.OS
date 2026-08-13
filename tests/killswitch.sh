#!/usr/bin/env bash
# Kill-switch leak test. Must run on Linux with a real wg0 and tcpdump.
# Fail closed: no wg0 → exit 2 (not a pass).
set -euo pipefail
IFACE="${1:-}"
[[ "$(uname -s)" == Linux ]] || { echo "skip: not Linux"; exit 2; }
command -v tcpdump >/dev/null || { echo "need tcpdump"; exit 1; }
command -v cicada-vpn >/dev/null || { echo "need cicada-vpn"; exit 1; }
ip link show wg0 >/dev/null 2>&1 || { echo "no wg0 — configure /etc/wireguard/wg0.conf first"; exit 2; }

if [[ -z "${IFACE}" ]]; then
  IFACE="$(ip -o route show default | awk '{print $5; exit}')"
fi
[[ -n "${IFACE}" ]] || { echo "no default iface"; exit 1; }

cicada-vpn on
tmp="$(mktemp)"
timeout 8 tcpdump -n -i "${IFACE}" -c 8 'not udp port 51820 and not arp and not icmp6' >"${tmp}" 2>&1 || true
# Drop the tunnel while capturing
ip link del wg0 || true
sleep 2
timeout 8 tcpdump -n -i "${IFACE}" -c 8 'not udp port 51820 and not arp and not icmp6' >>"${tmp}" 2>&1 || true

if grep -E 'IP |IP6 ' "${tmp}" | grep -vq '51820'; then
  echo "FAIL: packets on ${IFACE} outside WG handshake"
  cat "${tmp}"
  exit 1
fi
echo "PASS: no non-handshake packets on ${IFACE}"
rm -f "${tmp}"
