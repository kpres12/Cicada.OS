#!/usr/bin/env bash
# Walk the pending hardware matrix in docs/test-results.md on a real machine.
# Records pass/fail/skip with timestamps into docs/test-results.local.md (gitignored
# suggestion) or stdout. Does not claim a pass without evidence.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${CICADA_HW_RESULTS:-${ROOT}/docs/test-results.local.md}"
IS_LINUX=0
[[ "$(uname -s)" == Linux ]] && IS_LINUX=1

pass=0; fail=0; skip=0
results=()

record() {
  local status="$1" name="$2" note="${3:-}"
  results+=("| ${name} | ${status} | $(date -u +%Y-%m-%dT%H:%M:%SZ) | ${note} |")
  case "${status}" in
    pass) pass=$((pass + 1)) ;;
    fail) fail=$((fail + 1)) ;;
    *) skip=$((skip + 1)) ;;
  esac
  echo "[${status}] ${name}${note:+ — ${note}}"
}

need_linux() {
  [[ "${IS_LINUX}" -eq 1 ]] || { record skip "$1" "not Linux"; return 1; }
  return 0
}

echo "==> Cicada hardware validation"
echo "    writing: ${OUT}"

# --- Desktop surface --------------------------------------------------------
if need_linux "Live desktop surface"; then
  if pgrep -x Hyprland >/dev/null 2>&1 || pgrep -x hyprland >/dev/null 2>&1; then
    record pass "Hyprland session running"
  else
    record fail "Hyprland session running" "no Hyprland process"
  fi
  if pgrep -f nwg-dock-hyprland >/dev/null 2>&1; then
    record pass "Left dock (nwg-dock-hyprland)"
  else
    record fail "Left dock (nwg-dock-hyprland)" "not running"
  fi
  if pgrep -x waybar >/dev/null 2>&1 || pgrep -f waybar >/dev/null 2>&1; then
    record pass "Waybar"
  else
    record fail "Waybar" "not running"
  fi
  if pgrep -f swaync >/dev/null 2>&1 || pgrep -x swaync >/dev/null 2>&1; then
    record pass "Notification center (swaync)"
  else
    record fail "Notification center (swaync)" "not running"
  fi
  if pgrep -f 'pcmanfm-qt --desktop' >/dev/null 2>&1; then
    record pass "Desktop icons (pcmanfm-qt --desktop)"
  else
    record skip "Desktop icons (pcmanfm-qt --desktop)" "not detected — check visually"
  fi
fi

# --- Wi-Fi ------------------------------------------------------------------
if need_linux "Wi-Fi"; then
  if command -v nmcli >/dev/null 2>&1; then
    if nmcli -t -f DEVICE,STATE d | grep -q ':connected'; then
      record pass "Wi-Fi associated (nmcli)"
    else
      record fail "Wi-Fi associated (nmcli)" "no connected device — click dock Wi-Fi"
    fi
  else
    record skip "Wi-Fi associated" "nmcli missing"
  fi
fi

# --- Sandbox / malloc -------------------------------------------------------
if need_linux "hardened_malloc"; then
  if command -v cicada-malloc >/dev/null 2>&1; then
    if cicada-malloc status 2>/dev/null | grep -qi 'on\|enabled\|preload'; then
      record pass "hardened_malloc enabled"
    else
      record skip "hardened_malloc enabled" "opt-in off (expected default for Helium)"
    fi
  else
    record skip "hardened_malloc" "cicada-malloc missing"
  fi
fi

if need_linux "cicada-run landlock"; then
  if [[ -x /usr/local/lib/cicada/cicada-landlock-exec ]]; then
    record pass "Landlock helper present"
  else
    record fail "Landlock helper present"
  fi
  if grep -q landlock /sys/kernel/security/lsm 2>/dev/null; then
    record pass "Landlock in LSM list"
  else
    record fail "Landlock in LSM list" "check lsm= on cmdline / cicada-uki"
  fi
fi

# --- AFU --------------------------------------------------------------------
if need_linux "AFU USB gate"; then
  if command -v cicada-usb-gate >/dev/null 2>&1; then
    record pass "cicada-usb-gate installed"
  else
    record fail "cicada-usb-gate installed"
  fi
  if systemctl cat cicada-locked-reboot.timer >/dev/null 2>&1; then
    record pass "locked-reboot timer unit present"
  else
    record fail "locked-reboot timer unit present"
  fi
  echo "    MANUAL: lock with cicada-lock, insert USB, confirm blocked;"
  echo "            CICADA_LOCK_REBOOT_SEC=60 cicada-lock and wait for reboot."
  record skip "USB-while-locked + 30m reboot" "requires manual AFU exercise"
fi

# --- VPN --------------------------------------------------------------------
if need_linux "VPN kill switch"; then
  if command -v cicada-vpn >/dev/null 2>&1; then
    if cicada-vpn verify; then
      record pass "cicada-vpn verify (static policy)"
    else
      record fail "cicada-vpn verify (static policy)"
    fi
  else
    record fail "cicada-vpn missing"
  fi
  if [[ -f /etc/wireguard/wg0.conf ]] && grep -q '^PrivateKey' /etc/wireguard/wg0.conf; then
    echo "    MANUAL: tests/killswitch.sh <wlanIface> with a real endpoint"
    record skip "tcpdump kill-switch proof" "needs wg0 + tcpdump"
  else
    record skip "tcpdump kill-switch proof" "no wg0.conf yet"
  fi
fi

# --- Install ----------------------------------------------------------------
if need_linux "cicada-install"; then
  if [[ -e /etc/cicada/installed ]] || [[ -f /etc/cicada/INSTALL_ID ]]; then
    record pass "Installed system markers present"
  else
    record skip "cicada-install spare-disk smoke" "live image — install to spare disk"
  fi
fi

# --- Write report -----------------------------------------------------------
{
  echo "# Cicada hardware validation (local)"
  echo
  echo "Generated by scripts/hardware-validate.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
  echo "Host: $(uname -a)"
  echo
  echo "| Test | Result | UTC | Notes |"
  echo "|---|---|---|---|"
  printf '%s\n' "${results[@]}"
  echo
  echo "Summary: ${pass} pass / ${fail} fail / ${skip} skip"
} >"${OUT}"

echo
echo "==> ${pass} pass / ${fail} fail / ${skip} skip"
echo "    report: ${OUT}"
[[ "${fail}" -eq 0 ]]
