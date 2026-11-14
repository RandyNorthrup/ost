#!/usr/bin/env python3
"""Make OST's logo: a flat Fluent-style mark, an "OST" tile in front of two
people, in Fluent UI's brand purples. The wordmark is Selawik Bold (OFL,
desktop/assets/fonts), outlined so the SVG renders anywhere.

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

# Fluent UI brand ramp (the web palette Teams' UI is built on).
BRAND = {"60": "#444791", "70": "#4F52B2", "80": "#5B5FC7", "90": "#6D71D8", "100": "#7F85F5", "110": "#9299F7", "120": "#AAB1FA"}

# The tile and the wordmark.
TILE = (40, 196, 330, 276, 44)  # x, y, w, h, radius
CAP = 104                         # the letters' cap height


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


def svg():
    x, y, w, h, r = TILE
    letters = wordmark("OST", x + w / 2, y + h / 2, CAP)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <title>OST</title>
  <defs>
    <linearGradient id="back" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="{BRAND['120']}"/><stop offset="1" stop-color="{BRAND['100']}"/>
    </linearGradient>
    <linearGradient id="mid" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="{BRAND['100']}"/><stop offset="1" stop-color="{BRAND['80']}"/>
    </linearGradient>
    <linearGradient id="tile" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{BRAND['80']}"/><stop offset="1" stop-color="{BRAND['60']}"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <filter id="lift" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#1B1A4A" flood-opacity="0.28"/>
    </filter>
  </defs>
  <!-- The people behind the tile -->
  <circle cx="386" cy="132" r="46" fill="url(#back)"/>
  <rect x="318" y="192" width="150" height="232" rx="62" fill="url(#back)"/>
  <circle cx="262" cy="106" r="60" fill="url(#mid)"/>
  <rect x="166" y="184" width="200" height="252" rx="86" fill="url(#mid)"/>
  <!-- The tile and its wordmark -->
  <g filter="url(#lift)">
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#tile)"/>
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#sheen)"/>
  </g>
  <path d="{letters}" fill="#FFFFFF"/>
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
