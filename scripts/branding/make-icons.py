"""Draws the DoMa Talk icons (designed with Claude Code): the app icon (asset catalog and AppIcon.icns) and the menu bar
symbol. A head in profile that speaks: three flowing lines leave its mouth, words running on.
Run it again after a change:

    python3 -m pip install pillow
    python3 scripts/branding/make-icons.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "BlitztextMac" / "Resources"
ICONSET = RESOURCES / "Assets.xcassets" / "AppIcon.appiconset"

TOP = (52, 199, 189)      # teal
BOTTOM = (37, 99, 235)    # blue
SUPER = 4                 # drawn larger, then scaled down for smooth edges

# A head in profile facing right, drawn on classic proportions: top of the skull at 0, chin at
# 100, hairline, brow and nose base splitting the face in thirds; the neck leans slightly forward
# and runs on below the chin until the icon's edge cuts it off. The lips are parted at MOUTH.
HEAD = [
    # crown and forehead
    (44, 0), (60, 2), (72, 8), (80, 18), (84, 30), (85, 41),
    # brow, bridge and nose
    (86, 46), (84, 50), (89, 58), (95, 66), (96.5, 69), (94, 71), (88, 72),
    # lips, slightly apart, and chin
    (90, 75), (90.5, 77.5), (86.5, 80), (89.5, 82.5), (88, 86), (85, 88.5), (88, 93), (87, 98), (82, 101),
    # jaw underside, throat and the front of the neck
    (72, 102), (64, 105), (62, 120), (63, 145), (64, 200),
    # back of the neck, nape and the back of the skull
    (16, 200), (18, 145), (20, 118), (20, 104), (15, 94), (8, 80), (4, 62), (4, 46), (8, 28), (18, 12), (30, 3),
]
MOUTH = (87, 80)


def smooth(points, steps=24):
    """Catmull-Rom curve through the outline, closed, so the profile has no corners."""
    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % n], points[(i + 2) % n]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                for a, b, c, d in zip(p0, p1, p2, p3)
            ))
    return out


def wave(draw, x0, x1, y, amplitude, periods, width, fill):
    """A wavy line with round ends, stamped as discs so it stays clean at any width."""
    r = width / 2
    steps = max(200, int((x1 - x0) / max(r / 3, 0.5)))
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        yy = y + amplitude * math.sin(2 * math.pi * periods * t)
        draw.ellipse([x - r, yy - r, x + r, yy + r], fill=fill)


def speaking_head(draw, left, top, unit, waves_right, wave_width, amplitude, gap, fill, lines=3):
    outline = [(left + x * unit, top + y * unit) for x, y in smooth(HEAD)]
    draw.polygon(outline, fill=fill)
    mouth_x = left + MOUTH[0] * unit
    mouth_y = top + MOUTH[1] * unit
    start = mouth_x + 13 * unit
    offsets = (0,) if lines == 1 else ((-1, 1) if lines == 2 else (-1, 0, 1))
    lengths = {-1: 0.78, 0: 1.0, 1: 0.78}
    for row in offsets:
        end = start + (waves_right - start) * lengths[row]
        wave(draw, start, end, mouth_y + row * gap, amplitude, 1.25 * lengths[row], wave_width, fill)


def app_icon(size=1024):
    s = size * SUPER
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # Body on the macOS grid: about 89 % of the canvas, rounded like the system icons.
    inset = round(s * 0.0527)
    body = s - 2 * inset
    art = Image.new("RGBA", (body, body))
    pixels = art.load()
    for y in range(body):
        t = y / (body - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,)
        for x in range(body):
            pixels[x, y] = row
    speaking_head(
        ImageDraw.Draw(art), left=body * 0.07, top=body * 0.15, unit=body * 0.0058,
        waves_right=body * 0.92, wave_width=body * 0.046, amplitude=body * 0.021, gap=body * 0.1,
        fill=(255, 255, 255, 255),
    )
    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=round(body * 0.225), fill=255)
    image.paste(art, (inset, inset), mask)
    return image.resize((size, size), Image.LANCZOS)


def menubar_symbol(points):
    """The app icon's head and three lines, black on clear; macOS tints it (template image).
    Drawn with the icon's own layout, a little bolder so the lines hold at 18 points, then
    trimmed to the drawing and fitted into the square."""
    s = 1024
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    speaking_head(
        ImageDraw.Draw(canvas), left=s * 0.07, top=s * 0.15, unit=s * 0.0058,
        waves_right=s * 0.92, wave_width=s * 0.06, amplitude=s * 0.022, gap=s * 0.115,
        fill=(0, 0, 0, 255),
    )
    # The neck would run on; end it where the head's lowest line would be in the icon.
    canvas = canvas.crop((0, 0, s, round(s * 0.9)))
    drawing = canvas.crop(canvas.getbbox())
    side = max(drawing.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(drawing, ((side - drawing.width) // 2, side - drawing.height), drawing)
    return square.resize((points, points), Image.LANCZOS)


if __name__ == "__main__":
    master = app_icon(1024)
    names = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_64x64.png": 64, "icon_64x64@2x.png": 128,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
        "icon_1024x1024.png": 1024,
    }
    for name, size in names.items():
        master.resize((size, size), Image.LANCZOS).save(ICONSET / name, optimize=True)
    master.save(RESOURCES / "AppIcon.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    master.resize((256, 256), Image.LANCZOS).save(ROOT / "docs" / "assets" / "doma-talk-icon.png", optimize=True)
    menubar_symbol(18).save(RESOURCES / "menubar_icon.png")
    menubar_symbol(36).save(RESOURCES / "menubar_icon@2x.png")
    print("DoMa Talk icons written")
