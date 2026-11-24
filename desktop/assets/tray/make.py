#!/usr/bin/env python3
"""Make the tray's images: the OST logo with Teams' presence badge (as
Teams' tray icon carries it), and coloured presence icons for the tray
menu (the native menu can't tint), as SVG and the PNGs its DBus menu takes. Colours and glyphs as PresenceBadge.qml.

Run from the repo root: python3 -I desktop/assets/tray/make.py
(needs resvg and the venv Pillow at ~/.local/share/ost-vnc-venv)."""
import base64, os, subprocess, tempfile

ICONS = "desktop/assets/icons"
OUT = "desktop/assets/tray"
INK = {"available": "#13A10E", "away": "#EAA300", "busy": "#D13438", "dnd": "#D13438",
       "oof": "#C239B3", "offline": "#616161", "unknown": "#616161"}

def coloured(kind, size):
    svg = open(f"{ICONS}/presence-{kind}-{size}.svg").read().replace("#212121", INK[kind])
    # A white disc behind the glyph, as the badge draws it.
    s = size
    disc = f'<circle cx="{s/2}" cy="{s/2}" r="{s/2}" fill="#FFFFFF"/>'
    i = svg.index(">", svg.index("<svg")) + 1
    return svg[:i] + disc + svg[i:]

for kind in INK:
    open(f"{OUT}/presence-{kind}-16.svg", "w").write(coloured(kind, 16))
    # Tray icon: the logo at 64 px with a 28 px badge at the bottom right.
    logo = base64.b64encode(open("desktop/assets/logo.png", "rb").read()).decode()
    badge = coloured(kind, 20)
    inner = badge[badge.index(">", badge.index("<svg")) + 1: badge.rindex("</svg>")]
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64" viewBox="0 0 64 64">
<image width="64" height="64" xlink:href="data:image/png;base64,{logo}"/>
<g transform="translate(36 36) scale(1.4)">{inner}</g></svg>'''
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
    subprocess.run(["resvg", "-w", "64", "-h", "64", f.name, f"{OUT}/ost-{kind}.png"], check=True)
    os.unlink(f.name)
svg = open(f"{ICONS}/arrow-clockwise-20.svg").read().replace("#212121", "#424242")
open(f"{OUT}/reset-16.svg", "w").write(svg)
# The DBus tray menu takes PNG icons: the menu's, at 32 px for HiDPI.
for name in [f"presence-{k}-16" for k in INK] + ["reset-16"]:
    subprocess.run(["resvg", "-w", "32", "-h", "32", f"{OUT}/{name}.svg", f"{OUT}/{name}.png"], check=True)
print("ok")
