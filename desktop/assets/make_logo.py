#!/usr/bin/env python3
"""Make OST's logo: a wide "OST" plate in front of three people, drawn in
the style of Fluent's 2023 app icons. Everything is rounded and shaded with
smooth gradients in Fluent UI's brand purples: the plate runs from #4F52B2
down to #33357A, and the people are pale lavender tints so they stand apart
from it; a white gap cuts the plate out from the people (the user's choice,
2026-11-19, for contrast). A soft white light falls from the top left on heads and
bodies, and the plate casts a soft shadow on the people behind it. That
depth is built from linear and radial gradients laid over the shapes, with
no filters or clip paths, so Qt's SVG renderer draws it the same as resvg.

Teams' own mark is a square "T" plate at the front left with two people
behind it to the right. OST keeps the trade dress apart. Its plate is a
wide "OST" wordmark plate with no "T" shape, the letters are the largest
element, and nothing is traced from or copied out of Teams' artwork. There
are two layouts (see LAYOUTS):
  a (default, the user's choice on 2026-11-19) three people standing
               symmetrically behind a wide, centred plate (one in the
               middle, one at each side);
  b            the plate at the front lower left with two people behind it
               to the upper right.
The wordmark is Selawik Bold (OFL, desktop/assets/fonts), outlined so the
SVG renders anywhere.

Writes desktop/assets/logo.svg, desktop/assets/logo.png (512),
desktop/packaging/ost-desktop.png (256) and docs/logo_ost.png (512).
Run from the repo root with the helper venv (fontTools; resvg on PATH):
  ~/.local/share/ost-vnc-venv/bin/python -I desktop/assets/make_logo.py [--layout a]
then python3 -I desktop/assets/tray/make.py for the tray icons. To try a
layout without touching the app's assets, add --out DIR: that writes
DIR/logo.svg and DIR/logo-{512,256,48,24}.png only.
"""
import subprocess

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONT = "desktop/assets/fonts/selawkb.ttf"
OUT = "desktop/assets/logo.svg"

# Fluent UI brand ramp (the web palette Teams' UI is built on), and the
# lighter tints Fluent's app icons use for the parts further back.
BRAND = {"60": "#444791", "70": "#4F52B2", "80": "#5B5FC7", "90": "#6D71D8", "100": "#7F85F5",
         "110": "#9299F7", "120": "#AAB1FA", "140": "#C5CBFA", "icon": "#7B83EB", "deep": "#33357A"}

# The layouts. Each has its plate (x, y, w, h, radius), the letters' cap
# height, and its people from back to front. A person is an id, a fill
# ("side" is the lighter tint for those further back), the head (cx, cy, r),
# the body (x, y, w, h, radius), the strength of the light on it, and which
# of the plate's shadows fall on it.
LAYOUTS = {
    # A (the default, chosen by the user 2026-11-19): three people standing symmetrically behind a wide,
    # centred plate.
    "a": {
        "plate": (78, 220, 356, 240, 54), "cap": 108,
        "about": "Three people behind the plate: one at each side, one in the middle",
        "people": [
            ("L", "side", (100, 150, 45), (30, 210, 140, 226, 66), 0.38, ["castTop", "castL"]),
            ("R", "side", (412, 150, 45), (342, 210, 140, 226, 66), 0.38, ["castTop", "castR"]),
            ("C", "centre", (256, 112, 62), (150, 186, 212, 270, 96), 0.34, ["castTop"]),
        ],
    },
    # B: the earlier composition. The plate is at the front lower left, with
    # two people behind it to the upper right.
    "b": {
        "plate": (40, 196, 330, 276, 44), "cap": 104,
        "about": "Two people behind the plate, to its upper right",
        "people": [
            ("B", "side", (386, 132, 46), (318, 192, 150, 232, 62), 0.38, ["castR"]),
            ("M", "centre", (262, 106, 60), (166, 180, 200, 256, 86), 0.34, ["castTop"]),
        ],
    },
}


def wordmark(text, cx, cy, cap):
    """The text as one SVG path, its cap height `cap`, centred on (cx, cy)."""
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    cap_units = getattr(font["OS/2"], "sCapHeight", 0) or upm * 0.7
    k = cap / cap_units
    # Lay the glyphs out on the baseline, tightened a little as a logo is.
    names = [cmap[ord(c)] for c in text]
    x, placed = 0.0, []
    for i, n in enumerate(names):
        placed.append((n, x))
        x += glyphs[n].width - (upm * 0.02 if i < len(names) - 1 else 0)
    bounds = BoundsPen(glyphs)
    for n, dx in placed:
        glyphs[n].draw(TransformPen(bounds, (1, 0, 0, 1, dx, 0)))
    x0, y0, x1, y1 = bounds.bounds
    w = (x1 - x0) * k
    pen = SVGPathPen(glyphs)
    # Font units are y-up: flip, scale, and centre the ink box.
    ox, oy = cx - w / 2 - x0 * k, cy + cap / 2
    for n, dx in placed:
        glyphs[n].draw(TransformPen(pen, (k, 0, 0, -k, ox + dx * k, oy)))
    return pen.getCommands()


def glow(id_, cx, cy, r, alpha):
    """A soft white light from the top left, laid over a shape."""
    return (f'<radialGradient id="{id_}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">'
            f'<stop offset="0" stop-color="#FFFFFF" stop-opacity="{alpha}"/>'
            f'<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>')


def cast(id_, x1, y1, x2, y2, alpha):
    """The plate's shadow: dark at the plate's edge, gone `(x2, y2)` away."""
    return (f'<linearGradient id="{id_}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            f'<stop offset="0" stop-color="{BRAND["deep"]}" stop-opacity="{alpha}"/>'
            f'<stop offset="1" stop-color="{BRAND["deep"]}" stop-opacity="0"/></linearGradient>')


def person(head, body, fill, light, shadows):
    """A head and body, lit from the top left, with the plate's shadows on it.
    The shading is gradients over the person's own shapes rather than
    filters or clip paths, so Qt's SVG renderer draws it as resvg does."""
    (hx, hy, hr), (bx, by, bw, bh, br) = head, body
    disc = f'<circle cx="{hx}" cy="{hy}" r="{hr}" fill="url(#{{}})"/>'
    torso = f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="{br}" fill="url(#{{}})"/>'
    parts = [disc.format(fill), disc.format(light), torso.format(fill), torso.format(light)]
    parts += [torso.format(s) for s in shadows]
    return "\n  ".join(parts)


def svg(layout="a"):
    lay = LAYOUTS[layout]
    x, y, w, h, r = lay["plate"]
    b = BRAND
    letters = wordmark("OST", x + w / 2, y + h / 2 + 2, lay["cap"])
    reach = 30  # how far the plate's shadow falls
    # Each head's light sits up and to the left of its centre.
    lights = "\n    ".join(
        glow(f"light{pid}", hx - round(0.35 * hr), hy - round(0.48 * hr), hr * 1.6, alpha)
        for pid, _, (hx, hy, hr), _, alpha, _ in sorted(lay["people"]))
    people = "\n  ".join(person(head, body, fill, f"light{pid}", shadows)
                         for pid, fill, head, body, _, shadows in lay["people"])
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <title>OST</title>
  <defs>
    <linearGradient id="side" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0" stop-color="#E3E6FE"/><stop offset="1" stop-color="{b['140']}"/>
    </linearGradient>
    <linearGradient id="centre" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0" stop-color="#D3D8FC"/><stop offset="0.55" stop-color="{b['120']}"/><stop offset="1" stop-color="{b['110']}"/>
    </linearGradient>
    <linearGradient id="plate" x1="0" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{b['70']}"/><stop offset="0.5" stop-color="{b['60']}"/><stop offset="1" stop-color="{b['deep']}"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/><stop offset="0.4" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.8" stop-color="{b['deep']}" stop-opacity="0"/><stop offset="1" stop-color="{b['deep']}" stop-opacity="0.22"/>
    </linearGradient>
    <linearGradient id="ink" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4E6FF"/>
    </linearGradient>
    {lights}
    {cast("castTop", 0, y, 0, y - reach, 0.42)}
    {cast("castL", x, 0, x - reach, 0, 0.3)}
    {cast("castR", x + w, 0, x + w + reach, 0, 0.3)}
  </defs>
  <!-- {lay["about"]} -->
  {people}
  <!-- A white gap cuts the plate out from the people behind it -->
  <rect x="{x - 10}" y="{y - 10}" width="{w + 20}" height="{h + 20}" rx="{r + 10}" fill="#FFFFFF"/>
  <!-- The plate and its wordmark -->
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#plate)"/>
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#sheen)"/>
  <path d="{letters}" fill="url(#ink)"/>
</svg>
'''


def render(src, out, size):
    subprocess.run(["resvg", "-w", str(size), "-h", str(size), src, out], check=True)


if __name__ == "__main__":
    import argparse
    import os

    ap = argparse.ArgumentParser(description="Make OST's logo.")
    ap.add_argument("--layout", choices=sorted(LAYOUTS), default="a")
    ap.add_argument("--out", help="write logo.svg and logo-{512,256,48,24}.png into this "
                    "folder instead of the app's assets, to try a layout")
    args = ap.parse_args()
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        src = os.path.join(args.out, "logo.svg")
        open(src, "w").write(svg(args.layout))
        for size in (512, 256, 48, 24):
            render(src, os.path.join(args.out, f"logo-{size}.png"), size)
    else:
        open(OUT, "w").write(svg(args.layout))
        render(OUT, "desktop/assets/logo.png", 512)
        render(OUT, "desktop/packaging/ost-desktop.png", 256)
        render(OUT, "docs/logo_ost.png", 512)
    print("ok")
