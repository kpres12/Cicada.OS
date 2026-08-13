# Start Hyprland on tty1 for the live user.
if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty 2>/dev/null)" == /dev/tty1 ]]; then
  mkdir -p "${HOME}/.local/share/hypr"
  Hyprland >"${HOME}/.local/share/hypr/tty-start.log" 2>&1 \
    || echo "Hyprland failed. Ctrl+Alt+F2, empty password, see ~/.local/share/hypr/"
fi
