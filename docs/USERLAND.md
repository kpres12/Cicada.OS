# Own userland (without leaving Arch)

Cicada does **not** rebase to NixOS / Atomic / immutable Fedora. Arch stays the engine (see `.cursor/rules`). “Own userland” means **we own what the user sees and updates**, not that we fork glibc.

## What we own

| Surface | Cicada control |
|---|---|
| Identity | `PRETTY_NAME=Cicada.OS`, ASCII issue, boot titles, greeter greeting |
| Session | `cicada-session` → compositor (Hyprland is an implementation detail) |
| Login | greetd + tuigreet on etched installs (live stays autologin demo) |
| Apps | Helium pin, dock catalog, `cicada-run` scopes, `cicada-pkg` / Flatpak allowlist |
| Updates | `cicada-update` + `[cicada-stable]` before core/extra — not “just use Arch rolling” |
| Install | `cicada-etch` / `cicada-install` |

## What we deliberately do not own

- Kernel tree, pacman, systemd (upstream Arch).
- Replacing Hyprland unless something is clearly more secure *and* more daily-driveable on MBA-class hardware. Today nothing is: GNOME is heavier; Sway is less discoverable; Cosmic is immature; Nix rebase is out of scope.

## Next levers (still Arch engine)

1. Hosted signed `cicada-stable` mirror (users never add raw mirrors by hand).
2. Meta-package `cicada-desktop` that pulls the dock/desk/browser set as one unit.
3. Greeter theme / Cicada wallpaper behind tuigreet.
4. Hide remaining “hyprland” strings in Waybar module *keys* (internal JSON is fine; user-visible labels already say CICADA / WEB / FILES).
