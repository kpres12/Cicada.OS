# Start the Cicada desk on tty1 (Hyprland under the hood — never advertised).
if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty 2>/dev/null)" == /dev/tty1 ]]; then
  mkdir -p "${HOME}/.local/share/hypr"
  if [[ -t 1 ]]; then
    if [[ -x /usr/local/bin/cicada-banner ]]; then
      /usr/local/bin/cicada-banner
    fi
  fi
  Hyprland >"${HOME}/.local/share/hypr/tty-start.log" 2>&1 \
    || echo "Cicada desk failed to start. Ctrl+Alt+F2 — see ~/.local/share/hypr/tty-start.log"
fi
