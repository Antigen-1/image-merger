#!/usr/bin/env python3
"""Generate sample PNG fixtures for the image-merger demo.

Run with the project venv:

    .venv/bin/python examples/gen-fixtures.py
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
# 3:2 aspect on purpose, so `fit`, `fill` and `stretch` differ visibly in a
# 4:3 (160x120) cell.
COLORS = ["#e6194b", "#3cb44b", "#4363d8", "#f58231", "#911eb4", "#42d4f4"]
SIZE = (300, 200)


def main():
    for i, color in enumerate(COLORS):
        img = Image.new("RGB", SIZE, color)
        draw = ImageDraw.Draw(img)
        draw.text((16, 16), "image %d (%dx%d)" % (i, *SIZE), fill="white")
        img.save(os.path.join(HERE, "img%d.png" % i))
    print("wrote %d fixtures to %s" % (len(COLORS), HERE))


if __name__ == "__main__":
    main()
