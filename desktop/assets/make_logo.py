#!/usr/bin/env python3
"""Make OST's logo: a wide "OST" plate in front of three people, drawn in
the style of Fluent's 2023 app icons. Everything is rounded and shaded with
smooth gradients in Fluent UI's brand purples: the plate runs from #5B5FC7
down to #444791, the middle figure is a mid purple and the two side figures
lighter tints. A soft white light falls from the top left on heads and
bodies, and the plate casts a soft shadow on the people behind it. That
depth is built from linear and radial gradients laid over the shapes, with
no filters or clip paths, so Qt's SVG renderer draws it the same as resvg.

Teams' own mark is a square "T" plate at the front left with two people
behind it to the right. OST keeps the trade dress apart. Its wordmark plate
is wide and centred, with three people standing symmetrically behind it
(one in the middle, one at each side), and the "OST" letters are the
largest element. Nothing is traced from or copied out of Teams' artwork.
The wordmark is Selawik Bold (OFL, desktop/assets/fonts), outlined so the
SVG renders anywhere.

Writes desktop/assets/logo.svg, desktop/assets/logo.png (512),
desktop/packaging/ost-desktop.png (256) and docs/logo_ost.png (512).
Run from the repo root with the helper venv (fontTools; resvg on PATH):
  ~/.local/share/ost-vnc-venv/bin/python -I desktop/assets/make_logo.py
then python3 -I desktop/assets/tray/make.py for the tray icons.
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

# The plate and its wordmark: a wide plate, for three letters.
PLATE = (78, 220, 356, 240, 54)   # x, y, w, h, radius
CAP = 108                         # the letters' cap height
# The three people behind it: (head cx, cy, r), (body x, y, w, h, radius).
CENTRE = ((256, 112, 62), (150, 186, 212, 270, 96))
SIDES = [((100, 150, 45), (30, 210, 140, 226, 66)),
         ((412, 150, 45), (342, 210, 140, 226, 66))]


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


def svg():
    x, y, w, h, r = PLATE
    b = BRAND
    letters = wordmark("OST", x + w / 2, y + h / 2 + 2, CAP)
    (cx, cy, cr), _ = CENTRE
    (lx, ly, lr), _ = SIDES[0]
    (rx_, ry, rr), _ = SIDES[1]
    reach = 30  # how far the plate's shadow falls
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <title>OST</title>
  <defs>
    <linearGradient id="side" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0" stop-color="{b['140']}"/><stop offset="1" stop-color="{b['110']}"/>
    </linearGradient>
    <linearGradient id="centre" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0" stop-color="{b['120']}"/><stop offset="0.55" stop-color="{b['icon']}"/><stop offset="1" stop-color="{b['90']}"/>
    </linearGradient>
    <linearGradient id="plate" x1="0" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{b['80']}"/><stop offset="0.5" stop-color="{b['70']}"/><stop offset="1" stop-color="{b['60']}"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/><stop offset="0.4" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.8" stop-color="{b['deep']}" stop-opacity="0"/><stop offset="1" stop-color="{b['deep']}" stop-opacity="0.22"/>
    </linearGradient>
    <linearGradient id="ink" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4E6FF"/>
    </linearGradient>
    {glow("lightC", cx - 22, cy - 30, cr * 1.6, 0.34)}
    {glow("lightL", lx - 16, ly - 22, lr * 1.6, 0.38)}
    {glow("lightR", rx_ - 16, ry - 22, rr * 1.6, 0.38)}
    {cast("castTop", 0, y, 0, y - reach, 0.42)}
    {cast("castL", x, 0, x - reach, 0, 0.3)}
    {cast("castR", x + w, 0, x + w + reach, 0, 0.3)}
  </defs>
  <!-- Three people behind the plate: one at each side, one in the middle -->
  {person(*SIDES[0], "side", "lightL", ["castTop", "castL"])}
  {person(*SIDES[1], "side", "lightR", ["castTop", "castR"])}
  {person(*CENTRE, "centre", "lightC", ["castTop"])}
  <!-- The plate and its wordmark -->
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#plate)"/>
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#sheen)"/>
  <path d="{letters}" fill="url(#ink)"/>
</svg>
'''


def render(src, out, size):
    subprocess.run(["resvg", "-w", str(size), "-h", str(size), src, out], check=True)


if __name__ == "__main__":
    open(OUT, "w").write(svg())
    render(OUT, "desktop/assets/logo.png", 512)
    render(OUT, "desktop/packaging/ost-desktop.png", 256)
    render(OUT, "docs/logo_ost.png", 512)
    print("ok")
