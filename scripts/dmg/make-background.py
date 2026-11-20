"""Draws the background of the installer window (scripts/make-dmg.sh): an arrow from the
app to the Programme folder and a one-line hint. Run it again after changing the layout:

    python3 -m pip install pillow
    python3 scripts/dmg/make-background.py

The positions match the icon positions in make-dmg.sh (window 600 x 380, icons at
x 160 and 440, y 150).
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONTS = HERE.parent.parent / "BlitztextShared" / "Fonts"

WIDTH, HEIGHT = 600, 380
TOP, BOTTOM = (250, 248, 254), (238, 232, 249)
LILAC = (187, 132, 223)
TEXT = (74, 68, 92)
MUTED = (128, 122, 145)


def draw(scale: int) -> Image.Image:
    w, h = WIDTH * scale, HEIGHT * scale
    image = Image.new("RGB", (w, h))
    pixels = image.load()
    for y in range(h):
        t = y / (h - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        for x in range(w):
            pixels[x, y] = row

    pen = ImageDraw.Draw(image)
    # Arrow between the two icons, at their height.
    y = 150 * scale
    start, tip = 250 * scale, 350 * scale
    stroke = 6 * scale
    head = 16 * scale
    pen.line([(start, y), (tip - head, y)], fill=LILAC, width=stroke)
    pen.ellipse([start - stroke / 2, y - stroke / 2, start + stroke / 2, y + stroke / 2], fill=LILAC)
    pen.polygon([(tip, y), (tip - head * 1.4, y - head), (tip - head * 1.4, y + head)], fill=LILAC)

    title = ImageFont.truetype(str(FONTS / "PublicSans-SemiBold.ttf"), 16 * scale)
    note = ImageFont.truetype(str(FONTS / "PublicSans-Regular.ttf"), 12 * scale)
    pen.text((w / 2, 275 * scale), "Ziehe Blitztext auf den Ordner Programme.", font=title, fill=TEXT, anchor="mm")
    pen.text((w / 2, 300 * scale), "Danach Blitztext in Programme öffnen.", font=note, fill=MUTED, anchor="mm")
    return image


if __name__ == "__main__":
    draw(1).save(HERE / "background.png", optimize=True)
    draw(2).save(HERE / "background@2x.png", optimize=True)
    print("background.png, background@2x.png")
