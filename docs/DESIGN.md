# Cicada visual language

References: Sentry-style NEO trackers (phosphor HUD), Evangelion MAGI/VFD gauges, OT-era / Star Wars tactical consoles. Not generic cyberpunk purple.

Public site: [`site/`](../site/) (GitHub Pages) — same tokens.

## Tokens

| Token | Hex | Use |
|---|---|---|
| void | `#000000` | true black canvas |
| steel | `#0b0d10` | panels, waybar fill |
| grid | `#1a1f24` | inactive borders, selection |
| phosphor | `#39ff14` | titles, MAGI/SENTRY headers |
| magi | `#6cffc8` | secondary status, “all clear” |
| amber | `#ffb000` | data, clocks, body text |
| alert | `#ff3b00` | RF block, lock, wipe, warnings |
| path | `#c45c26` | inactive traces |

Type: JetBrains Mono + Share Tech (site mark). HUD labels are ALL CAPS, tracked out, never sentence case.

## Rules

- Square corners. No drop shadows. Thin 1–2px borders.
- Density over chrome: status is a console, not a candy bar.
- Motion is status (workspace slide / orbital drift), not decoration.
- Green = identity / live. Amber = telemetry. Red = hostile or blocked.
- CRT bloom is CSS glow on titles only — do not blur the whole desktop.
- Site hero: brand first (`CICADA.OS`), one headline, one lede, CTA row, full-bleed wireframe sentry — no card grid in the first viewport.

## Shell mapping (v0)

- **Waybar** = Sentry header (`CICADA // MAGI-01`, USR profile, SCOPES, RF, Zulu clock)
- **Super+I** = MAGI-02 scopes panel (per-app permission sheet)
- **Super+L** = MAGI-03 lock (hyprlock)
- **Super+Space** = phosphor wofi launcher
- **Hyprland dwindle** = MAGI panes (no rounding, phosphor active / steel inactive)
- **Kitty** = amber-on-void data feed
- **Wallpaper** = `usr/share/cicada/wallpapers/cicada-void.png`
