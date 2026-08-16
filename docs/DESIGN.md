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

## The mark

A cicada seen from above — wings spread, body segmented — in phosphor on
nothing. Identity is the one thing phosphor names, so the mark is never amber,
never filled with a background plate, and never boxed in a rounded tile.

Generated, not hand-drawn: `scripts/gen-cicada-icon.py` emits the whole hicolor
set from one geometry, so proportions stay in register across sizes. Detail is a
function of size, and the cutoffs come from looking at rasterised pixels rather
than from taste:

| Sizes | Treatment |
|---|---|
| 16–32 | solid silhouette, optically bolded (hairlines and the vein fan collide into a blob below 48) |
| 48 | line art, two veins, three segment rules |
| 64+ and `scalable` | full drawing — four veins, five rules, eyes |

Installed as `cicada` in `/usr/share/icons/hicolor`, which is the fallback every
theme inherits, so `Icon=cicada` resolves no matter what icon theme is set. This
is the name `os-release` already declares in `LOGO=`. It marks Cicada's own
surfaces — `Start here`, the session entries, the site favicon — and not
individual apps: Terminal and Files keep their Papirus icons, because a launcher
where every row is the same green cicada is a launcher you cannot scan.

To change the mark, edit the geometry constants and re-run the script; do not
hand-edit the SVGs, they are build output.

## Panel grammar

Every readout region is built the same way, so the bar, the launcher, the lock and the pattern bay read as one instrument rather than four themes.

1. **Panel** — a 1px `path` hairline box. Square. No fill beyond `void`, no shadow, no blur.
2. **Label tab** — a caps, tracked-out block on the panel's leading edge, either inverted (`path` fill, `void` text) or outlined. This is the `HELIO MAP` / `DATA FEED` construction; it names the instrument.
3. **Readouts** — monospace, fixed width, separated by `grid` hairlines. A gauge must not change width as its digits change; a console that reflows every two seconds reads as noise.
4. **Legend row** — glyph + caps label + value, at the foot of the panel. Says what the marks mean and which keys act.
5. **Ruler** — tick marks as a scale, with the cursor tick in `phosphor`. Position through a set is shown, not narrated.

Colour carries state, not decoration: `phosphor` = identity or live selection, `magi` = live data, `amber` = structure and primary values, `path` = held or inactive, `alert` = hostile, blocked, or thermally out of range.

## Shell mapping (v0)

- **Waybar** = Sentry header — `CICADA` mark, nav, USR profile, `MAGI-01` gauge panel (CPU/GPU/MEM/TMP), `SYS` panel (net/vol/bri/bat), Zulu + local clock
- **Super+I** = MAGI-02 scopes panel (per-app permission sheet)
- **Super+L** = MAGI-03 lock (hyprlock) — static plate, `hide_input`, no media, no session contents
- **Super+B** = MAGI-04 pattern bay (`cicada-wallpapers`) — wallpaper selector, phosphor reticle on the live plate
- **Super+Space** = phosphor wofi launcher
- **Hyprland dwindle** = MAGI panes (no rounding, phosphor active / steel inactive)
- **Kitty** = amber-on-void data feed
- **Wallpaper** = `usr/share/cicada/wallpapers/cicada-void.png`

## Lock screen is not a surface for features

MAGI-03 shows time, date, and one input. It does not show now-playing, notification counts, hostname, or a blurred screenshot of the session. Everything on it is read by whoever picks the machine up, not by the owner. Blur is not redaction — window titles and document text survive it well enough to read.
