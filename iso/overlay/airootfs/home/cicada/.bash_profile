# Start Hyprland on tty1 for the live user.
if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty 2>/dev/null)" == /dev/tty1 ]]; then
  Hyprland || echo "Hyprland failed. Root console: Ctrl+Alt+F2 (empty password)."
fi
