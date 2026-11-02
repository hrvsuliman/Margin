"""Draws the placeholder app icon: ruled paper, a red margin line and a hand-drawn "M".

Run from the repo root:  python Design/make_icon.py
Needs Pillow (pip install pillow). Writes a 1024x1024 RGB PNG (no transparency,
which iOS app icons must not have).
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # draw large, then shrink, for smooth edges
S = SIZE * SCALE

PAPER = (246, 243, 236)
RULING = (203, 214, 226)
MARGIN = (212, 81, 59)
INK = (28, 27, 31)


def catmull_rom(points, steps=24):
    """Smooth curve through the given points."""
    pts = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t
                       + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                for k in range(2)
            ))
    out.append(points[-1])
    return out


def main():
    img = Image.new("RGB", (S, S), PAPER)
    draw = ImageDraw.Draw(img)

    spacing = 112 * SCALE
    y = 168 * SCALE
    while y < S:
        draw.line([(0, y), (S, y)], fill=RULING, width=5 * SCALE)
        y += spacing

    margin_x = 238 * SCALE
    draw.line([(margin_x, 0), (margin_x, S)], fill=MARGIN, width=9 * SCALE)

    # A loose, hand-written capital M sitting on a ruled line.
    m = [(372, 728), (398, 520), (430, 362), (468, 470), (548, 640),
         (618, 450), (668, 352), (706, 520), (742, 728)]
    # Stamp a round brush densely along the curve (thick PIL lines leave gaps at joints).
    stroke = catmull_rom([(x * SCALE, y * SCALE) for x, y in m], steps=400)
    r = 23 * SCALE
    for x, y in stroke:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=INK)

    out = Path(__file__).resolve().parent.parent / "Margin/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    img.resize((SIZE, SIZE), Image.LANCZOS).save(out, "PNG")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
