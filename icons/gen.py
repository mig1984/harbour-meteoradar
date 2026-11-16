#!/usr/bin/env python3
"""Generate launcher icons: dark rounded square with concentric radar rings
(green/yellow/red precipitation blobs) and a centre dot."""
import math
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SIZES = [86, 108, 128, 172]
SS = 4  # supersampling


def make(size):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=(10, 26, 36, 255))

    cx, cy = s * 0.5, s * 0.5
    # radar "blobs": coloured sectors around the centre
    blobs = [
        (0.20, 0.00, (60, 200, 90, 255)),
        (0.30, 1.10, (230, 220, 40, 255)),
        (0.24, 2.40, (250, 140, 30, 255)),
        (0.16, 3.60, (230, 40, 40, 255)),
        (0.22, 4.70, (60, 200, 90, 255)),
    ]
    for r, ang, col in blobs:
        x = cx + math.cos(ang) * s * 0.22
        y = cy + math.sin(ang) * s * 0.22
        rr = r * s
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col)

    # rings
    w = max(2, int(s * 0.012))
    for k in (0.18, 0.34, 0.46):
        rad = s * k
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad],
                  outline=(180, 220, 235, 110), width=w)

    # centre dot (position)
    dot = s * 0.045
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(90, 170, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


for sz in SIZES:
    out = os.path.join(HERE, f"{sz}x{sz}")
    os.makedirs(out, exist_ok=True)
    img = make(sz).quantize(colors=64, method=Image.Quantize.FASTOCTREE)
    img.save(os.path.join(out, "harbour-meteoradar.png"), optimize=True)
    print("wrote", sz)
