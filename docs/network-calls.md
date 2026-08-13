# Network calls the live image is allowed to make

Anything not on this list is a bug. NetworkManager connectivity checks are disabled.

| When | Dest | Why | Control |
|---|---|---|---|
| User enables Wi-Fi and associates | DHCP (udp/67-68), local DNS | Get an address | User click (dock / Super+N) |
| TLS to user-chosen sites | 443/tcp | Browser, pacman, git | User |
| systemd-timesyncd | NTP (udp/123) to Arch NTP | TLS cert validity | Allowed. Do not disable or HTTPS breaks. |
| pacman -Sy | Arch HTTPS mirrors | Updates | Manual / install |
| WireGuard handshake | udp/51820 to configured endpoint | `cicada-vpn on` only | Opt-in |
| iwd/NM scan | local 802.11 | SSID list | After radio unblock |

Explicitly disabled:

- NetworkManager connectivity HTTP probe (`connectivity.enabled=false`)
- Chromium metrics / sync / url-keyed anonymized data / Google DoH (managed policy)
- LLMNR and mDNS (`systemd-resolved` Cicada drop-in)
- cloud-init (stripped from releng)
- sshd (masked)
- inbound unsolicited (nftables `cicada` table policy drop)

Not yet: a forced default WireGuard endpoint. Kill switch is off until `cicada-vpn on` so first-boot Wi-Fi still works.
