# Upstream snapshots

Cicada is a Helium-style remix: we do not reimplement Linux or a compositor.

| Path | Upstream | Why it is here |
|---|---|---|
| `vendor/archiso` | https://gitlab.archlinux.org/archlinux/archiso | Official live-ISO tooling + `releng` profile. ISO builds prefer the `archiso` package inside Docker, and fall back to this tree. |
| `vendor/Hyprland` | https://github.com/hyprwm/Hyprland | Compositor source for later Cicada shell work. The ISO installs Arch's `hyprland` package; this tree is for reading, patching, and eventually carrying our own package. |

Update:

```bash
git submodule update --init --recursive
git -C vendor/archiso pull --ff-only
git -C vendor/Hyprland pull --ff-only
git -C vendor/Hyprland submodule update --init --recursive
```

Licenses stay with upstream (archiso: GPL; Hyprland: BSD).
