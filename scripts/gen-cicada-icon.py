#!/usr/bin/env python3
"""Generate the Cicada.OS brand mark as a multi-size hicolor icon set.

The mark is a cicada seen from above: wings spread wide, body vertical and
segmented — the silhouette the project is named for. It is drawn in the shell's
own grammar (docs/DESIGN.md): hairline strokes, square joins, phosphor as
identity. Geometry lives here rather than in hand-edited SVGs so the proportions
stay adjustable and every size stays in register with the others.

Detail is a function of size, the way real icon themes do it. A 1px hairline and
five wing veins are the point of the mark at 64px and an unreadable smudge at
16px, so small sizes get a solid silhouette of the same shape instead of a
shrunken copy of the line art.

The normal repository output also refreshes the site's favicon from the same
scalable drawing. A custom --out is isolated and does not touch the site.

Usage:  python3 scripts/gen-cicada-icon.py [--out DIR] [--preview FILE]
"""

from __future__ import annotations

import argparse
import os
import sys

# docs/DESIGN.md tokens. Identity is phosphor; the mark carries no other colour.
PHOSPHOR = "#39ff14"

# Every file is authored in this square user-space box and scaled by the
# renderer, so a coordinate means the same thing at every size.
BOX = 64.0
CX = 32.0

# Nominal sizes hicolor declares an apps/ directory for. 22 and 24 are the
# panel/toolbar sizes Papirus and Qt actually ask for, so they are not optional.
SIZES = (16, 22, 24, 32, 48, 64, 128, 256)
DEFAULT_OUT = "packages/cicada-shell/files/usr/share/icons/hicolor"
SITE_MARK = "site/assets/svg/cicada-mark.svg"

# Detail tiers. These cutoffs were set by rasterising the mark and looking at
# the pixels, not by taste: below 48 the hairlines and the vein fan collide into
# a solid green blob, and at 48 the full fan is still muddy. So 32 and down get
# the silhouette, 48 gets a thinned fan, and only 64+ gets the whole drawing.
SILHOUETTE_MAX = 32
LITE_MAX = 48


# --- line-art geometry (32px and up) ---------------------------------------

HEAD_TOP, HEAD_BOT = 16.6, 21.0
THORAX_BOT = 29.5
ABDOMEN_TIP = 48.0

# Half-width of the abdomen down its length, as (y, half-width) knots. The taper
# is read off this table so the segment rules always land on the outline instead
# of poking through it. Kept short and blunt: a cicada's abdomen stops well
# inside the wingspan, and stretching it to a point turns the mark into a wasp.
ABDOMEN = (
    (THORAX_BOT, 4.4),
    (34.0, 4.2),
    (39.0, 3.6),
    (43.5, 2.7),
    (46.2, 1.7),
    (ABDOMEN_TIP, 0.9),
)


def n(v: float) -> str:
    """Trim a coordinate to 2dp and drop the trailing zeros.

    Float arithmetic on the taper table otherwise emits things like
    `28.337777777777777`, which bloats every file and makes a diff of the
    generated set unreadable when a knot moves.
    """
    return f"{round(v, 2):g}"


def abdomen_half_width(y: float) -> float:
    """Linear interpolation across the ABDOMEN knots."""
    for (y0, w0), (y1, w1) in zip(ABDOMEN, ABDOMEN[1:]):
        if y0 <= y <= y1:
            return w0 + (w1 - w0) * (y - y0) / (y1 - y0)
    return 0.0


def head_path() -> str:
    # A cicada's head is mostly two wide-set eyes, so the widest point sits at
    # the top corners and the outline steps in to meet the thorax.
    return (
        f"M {n(CX - 2.4)},{n(HEAD_TOP)} L {n(CX + 2.4)},{n(HEAD_TOP)} "
        f"L {n(CX + 4.5)},{n(HEAD_TOP + 1.6)} L {n(CX + 4.1)},{n(HEAD_BOT)} "
        f"L {n(CX - 4.1)},{n(HEAD_BOT)} L {n(CX - 4.5)},{n(HEAD_TOP + 1.6)} Z"
    )


def thorax_path() -> str:
    return (
        f"M {n(CX - 4.1)},{n(HEAD_BOT)} L {n(CX + 4.1)},{n(HEAD_BOT)} "
        f"L {n(CX + 4.9)},{n(HEAD_BOT + 3.6)} L {n(CX + 4.4)},{n(THORAX_BOT)} "
        f"L {n(CX - 4.4)},{n(THORAX_BOT)} L {n(CX - 4.9)},{n(HEAD_BOT + 3.6)} Z"
    )


def abdomen_path() -> str:
    # Walk the right edge from the neck down to the tip, then the left edge back
    # up. Both sides must include the final knot: now that the abdomen ends in a
    # blunt stub rather than a point, dropping the tip's mirror closes the shape
    # on a slant and the body looks snapped off.
    pts = [(CX + w, y) for y, w in ABDOMEN]
    pts += [(CX - w, y) for y, w in reversed(ABDOMEN)]
    return "M " + " L ".join(f"{n(x)},{n(y)}" for x, y in pts) + " Z"


def segment_rules(lite: bool = False) -> list[str]:
    """Horizontal rules across the abdomen — the mark's only repeating texture.

    Five rules across a 7-unit body is a 1px-on-1px-off comb once it lands on a
    48px grid, which renders as a filled bar. The lite tier keeps three.
    """
    out = []
    for y in ((33.4, 37.6, 41.8) if lite else (32.6, 35.6, 38.6, 41.4, 44.0)):
        w = abdomen_half_width(y) - 0.6
        out.append(f"M {n(CX - w)},{n(y)} L {n(CX + w)},{n(y)}")
    return out


# Wings are held as control points rather than path strings so the veins can be
# sampled off the real trailing edge. Hand-placed vein endpoints drift outside
# the outline the moment the wing shape is retuned, and a vein poking through
# the edge is the one error that makes the mark look broken rather than stylised.
#
# Each wing: root_top -> (c1, c2) -> tip along the leading edge, then
# tip -> (c3, c4) -> root_bot back along the trailing edge.
FOREWING = dict(
    root_top=(35.4, 20.6),
    lead=((44.0, 19.0), (54.0, 23.4)),
    tip=(60.5, 32.6),
    trail=((52.5, 35.4), (43.5, 34.2)),
    root_bot=(36.4, 29.9),
)
# The hindwing roots inside the forewing's root so the pair reads as one hinge.
# Rooted any lower it detaches and the mark grows a spare pair of leaves.
HINDWING = dict(
    root_top=(36.0, 26.6),
    lead=((43.5, 29.0), (48.8, 33.4)),
    tip=(51.0, 40.4),
    trail=((45.6, 39.0), (39.4, 35.0)),
    root_bot=(36.4, 30.6),
)

# Vein fan: (t along the wing root, t along the trailing edge). t runs from the
# tip (0) to the root (1), so the long leading vein is first.
VEIN_FAN = ((0.10, 0.10), (0.30, 0.33), (0.50, 0.56), (0.70, 0.76))


def bezier(p0, c1, c2, p3, t):
    u = 1.0 - t
    return (
        u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p3[0],
        u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p3[1],
    )


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def wing_path(w) -> str:
    return (
        f"M {w['root_top'][0]},{w['root_top'][1]} "
        f"C {w['lead'][0][0]},{w['lead'][0][1]} {w['lead'][1][0]},{w['lead'][1][1]} "
        f"{w['tip'][0]},{w['tip'][1]} "
        f"C {w['trail'][0][0]},{w['trail'][0][1]} {w['trail'][1][0]},{w['trail'][1][1]} "
        f"{w['root_bot'][0]},{w['root_bot'][1]} Z"
    )


def vein_paths(w, inset: float = 0.12) -> list[str]:
    """Veins from the wing root out to sampled points on the trailing edge.

    `inset` pulls each endpoint back along its own line so the vein dies just
    shy of the outline instead of merging into it and thickening the edge.
    """
    out = []
    for root_t, edge_t in VEIN_FAN:
        start = lerp(w["root_top"], w["root_bot"], root_t)
        start = lerp(start, w["tip"], 0.06)  # nudge clear of the body
        end = bezier(w["tip"], w["trail"][0], w["trail"][1], w["root_bot"], edge_t)
        end = lerp(end, start, inset)
        out.append(
            f"M {start[0]:.2f},{start[1]:.2f} L {end[0]:.2f},{end[1]:.2f}"
        )
    return out


# --- silhouette geometry (24px and down) -----------------------------------
#
# Same creature, fewer promises: one fused wing mass per side and a body wide
# enough to survive a 2px column. Proportions are pulled in from the line art —
# a 16px icon that keeps the 64px aspect ratio just draws a thinner smudge.

# Blunt outer ends, not points: a wing that tapers to nothing loses its last
# three pixels to antialiasing and the mark reads as a bird instead of an insect.
S_WING = (
    "M 34.4,19.4 C 46,17.6 56,21.4 60.8,29.2 "
    "C 60.2,32.0 56.6,33.6 53.2,33.9 "
    "C 44.4,34.6 37.8,32.6 34.8,30.0 Z"
)
S_HINDWING = (
    "M 35.2,27.8 C 43,29.4 48.6,33.2 50.6,40.6 "
    "C 44.6,40.2 38.6,36.0 35.2,31.6 Z"
)
S_BODY = (
    f"M {CX - 3.2},{14.8} L {CX + 3.2},{14.8} L {CX + 5.2},{20.4} "
    f"L {CX + 5.0},{29.5} L {CX + 3.0},{43.0} L {CX + 1.2},{49.5} "
    f"L {CX - 1.2},{49.5} L {CX - 3.0},{43.0} L {CX - 5.0},{29.5} "
    f"L {CX - 5.2},{20.4} Z"
)


def mirrored(body: str) -> str:
    """Emit a group and its mirror about CX, so the two halves cannot drift."""
    return (
        f'  <g>\n{body}  </g>\n'
        f'  <g transform="translate({CX * 2},0) scale(-1,1)">\n{body}  </g>\n'
    )


def build(size: int) -> str:
    """Return the SVG source for one nominal pixel size."""
    silhouette = size <= SILHOUETTE_MAX
    lite = not silhouette and size <= LITE_MAX
    # Aim every hairline at ~1.15 device pixels so the mark keeps the same
    # visual weight from 32px to 256px instead of thinning out as it grows.
    sw = round(BOX / size * 1.15, 3)

    head = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {BOX:.0f} {BOX:.0f}" '
        f'width="{size}" height="{size}" fill="none" role="img" '
        f'aria-label="Cicada.OS">\n'
        f"  <title>Cicada.OS</title>\n"
    )

    if silhouette:
        # Optical bolding. A shape scaled down loses its thinnest limbs to
        # antialiasing first, so the wing tips grey out and the mark reads as a
        # bird. Stroking the silhouette in its own colour re-thickens every edge
        # by half the stroke, and the smaller the icon the more it needs.
        bold = round(max(0.0, (30 - size) * 0.09), 3)
        # 16px also gets a little more of the box: at that size the margin costs
        # more than it buys.
        grow = 1.08 if size <= 16 else 1.0

        wings = f'    <path d="{S_WING}"/>\n    <path d="{S_HINDWING}"/>\n'
        inner = mirrored(wings) + f'    <path d="{S_BODY}"/>\n'
        attrs = f'fill="{PHOSPHOR}"'
        if bold:
            attrs += (
                f' stroke="{PHOSPHOR}" stroke-width="{bold}" '
                f'stroke-linejoin="round"'
            )
        body = f"  <g {attrs}>\n{inner}  </g>\n"
        if grow != 1.0:
            body = (
                f'  <g transform="translate({CX},{CX}) scale({grow}) '
                f'translate({-CX},{-CX})">\n{body}  </g>\n'
            )
        return head + body + "</svg>\n"

    wing = (
        f'    <path d="{wing_path(FOREWING)}"/>\n'
        f'    <path d="{wing_path(HINDWING)}"/>\n'
    )
    fan = vein_paths(FOREWING)
    if lite:
        fan = [fan[0], fan[2]]  # keep the leading vein and one mid-wing rib
    veins = "".join(f'    <path d="{v}"/>\n' for v in fan)
    eye = (
        f'    <circle cx="{CX - 3.5}" cy="{HEAD_TOP + 1.9}" r="0.7" '
        f'fill="{PHOSPHOR}"/>\n'
    )

    out = [head]
    out.append(
        f'  <g stroke="{PHOSPHOR}" stroke-width="{sw}" stroke-linecap="square" '
        f'stroke-linejoin="miter">\n'
    )
    out.append(mirrored(wing))
    out.append(mirrored(veins))
    out.append(f'    <path d="{head_path()}"/>\n')
    out.append(f'    <path d="{thorax_path()}"/>\n')
    out.append(f'    <path d="{abdomen_path()}"/>\n')
    for rule in segment_rules(lite):
        out.append(f'    <path d="{rule}"/>\n')
    out.append("  </g>\n")
    # Eyes are solid: the one place the mark reads as a creature looking back.
    out.append(f'  <g>\n{eye}  </g>\n')
    out.append(
        f'  <g transform="translate({CX * 2},0) scale(-1,1)">\n{eye}  </g>\n'
    )
    out.append("</svg>\n")
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--out",
        default=DEFAULT_OUT,
        help="hicolor theme root to write into",
    )
    ap.add_argument("--preview", help="also write a black contact sheet here")
    args = ap.parse_args()

    written = []
    for size in SIZES:
        d = os.path.join(args.out, f"{size}x{size}", "apps")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "cicada.svg")
        with open(p, "w") as fh:
            fh.write(build(size))
        written.append((size, p))

    # scalable/ is what asks-for-any-size consumers (greeters, hostnamectl,
    # about panels) actually pick up. It tracks the largest line-art drawing.
    d = os.path.join(args.out, "scalable", "apps")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "cicada.svg")
    scalable = build(256).replace('width="256" height="256" ', "")
    with open(p, "w") as fh:
        fh.write(scalable)
    written.append(("scalable", p))

    # The website favicon is the same brand surface, not a second drawing.
    # Only update it during the normal repository build: callers using --out
    # for a package root or reproducibility check must remain self-contained.
    if os.path.normpath(args.out) == os.path.normpath(DEFAULT_OUT):
        os.makedirs(os.path.dirname(SITE_MARK), exist_ok=True)
        with open(SITE_MARK, "w") as fh:
            fh.write(scalable)

    for size, path in written:
        print(f"{str(size):>8}  {path}")
    if os.path.normpath(args.out) == os.path.normpath(DEFAULT_OUT):
        print(f"{'site':>8}  {SITE_MARK}")

    if args.preview:
        row = "".join(
            f'<figure><img src="{os.path.relpath(p, os.path.dirname(args.preview))}" '
            f'width="{s}" height="{s}"><figcaption>{s}</figcaption></figure>'
            for s, p in written
            if s != "scalable"
        )
        with open(args.preview, "w") as fh:
            fh.write(
                "<html><body style='background:#000;margin:0;padding:24px;"
                "font:11px monospace;color:#ffb000'>"
                "<div style='display:flex;align-items:flex-end;gap:22px'>"
                + row
                + "</div>"
                "<div style='display:flex;align-items:flex-end;gap:22px;margin-top:28px'>"
                + row.replace("<figcaption>", "<figcaption>@2x ")
                + "</div>"
                "<style>figure{margin:0;text-align:center}"
                "figcaption{margin-top:8px;color:#c45c26}</style>"
                "</body></html>"
            )
        print(f"preview   {args.preview}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
