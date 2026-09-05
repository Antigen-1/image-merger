"""Pure-Python backend for image-merger (uses Pillow).

This module exposes a single entry point, :func:`merge`, which is called from
the Chez Scheme side through chez-python.  The argument ``spec`` is a nested
list (no dicts, no symbols — see ``(image-merger spec)``) with the shape::

    [output, width, height, background,
     items,           # each: [file, x, y, w, h, mode, align-h, align-v, ew, eh]
     row_labels,      # each: [text, x, y, w, h, align-h, align-v, font, size, color]
     column_labels]

It can also be run standalone from a virtual environment for debugging::

    python imagemerger.py spec.json
"""
from __future__ import annotations

from PIL import Image, ImageDraw, ImageFont

_H_ALIGN = ("left", "center", "right")
_V_ALIGN = ("top", "middle", "bottom")
_SCALE = ("fit", "fill", "stretch", "none", "exact")


def _open_rgba(path):
    return Image.open(path).convert("RGBA")


def _align_offset(delta, where):
    if where == "left" or where == "top":
        return 0
    if where == "center" or where == "middle":
        return delta // 2
    if where == "right" or where == "bottom":
        return delta
    raise ValueError("unknown alignment: %r" % where)


def _paste_into(canvas, image, x, y, w, h, mode, align_h, align_v, ew, eh):
    """Scale/crop ``image`` into the cell rect (x, y, w, h) and paste it."""
    x, y, w, h = int(x), int(y), int(w), int(h)

    if mode == "stretch":
        tw, th = w, h
    elif mode == "exact":
        tw, th = int(ew), int(eh)
    elif mode == "none":
        tw, th = image.size
    elif mode in ("fit", "fill"):
        iw, ih = image.size
        if iw <= 0 or ih <= 0:
            return
        scale = (min if mode == "fit" else max)(w / iw, h / ih)
        tw, th = int(round(iw * scale)), int(round(ih * scale))
    else:
        raise ValueError("unknown scale mode: %r" % mode)

    tw, th = max(1, tw), max(1, th)
    if (tw, th) != image.size:
        image = image.resize((tw, th), Image.Resampling.LANCZOS)

    # offset of the (possibly larger) image inside the cell rect
    ox = _align_offset(w - tw, align_h)
    oy = _align_offset(h - th, align_v)

    # clip to the cell so nothing overflows into neighbours or margins
    left = max(0, -ox)
    top = max(0, -oy)
    right = min(tw, w - ox)
    bottom = min(th, h - oy)
    cropped = image.crop((left, top, right, bottom))
    if cropped.size[0] <= 0 or cropped.size[1] <= 0:
        return
    canvas.paste(cropped, (x + max(0, ox), y + max(0, oy)), cropped)


def _anchor_point(x, y, w, h, align_h, align_v):
    ax = x if align_h == "left" else (x + w / 2 if align_h == "center" else x + w)
    ay = y if align_v == "top" else (y + h / 2 if align_v == "middle" else y + h)
    return ax, ay


def _anchor_str(align_h, align_v):
    h = {"left": "l", "center": "m", "right": "r"}[align_h]
    v = {"top": "t", "middle": "m", "bottom": "b"}[align_v]
    return h + v


def _draw_label(draw, text, x, y, w, h, align_h, align_v, font, size, color):
    if font:
        font_obj = ImageFont.truetype(font, int(size))
    else:
        font_obj = ImageFont.load_default()
    ax, ay = _anchor_point(x, y, w, h, align_h, align_v)
    draw.text((ax, ay), text, font=font_obj, fill=color,
              anchor=_anchor_str(align_h, align_v))


def merge(spec):
    output, width, height, background, items, row_labels, column_labels = spec

    transparent = background == "transparent"
    mode = "RGBA" if transparent else "RGB"
    canvas = Image.new(mode, (int(width), int(height)),
                       None if transparent else background)

    for item in items:
        file, x, y, w, h, smode, ah, av, ew, eh = item
        _paste_into(canvas, _open_rgba(file), x, y, w, h, smode, ah, av, ew, eh)

    draw = ImageDraw.Draw(canvas)
    for label in list(row_labels) + list(column_labels):
        text, x, y, w, h, ah, av, font, size, color = label
        _draw_label(draw, text, x, y, w, h, ah, av, font, size, color)

    canvas.save(output)
    return output


if __name__ == "__main__":
    import json
    import sys

    if len(sys.argv) != 2:
        sys.exit("usage: imagemerger.py spec.json")
    with open(sys.argv[1], encoding="utf-8") as fh:
        print(merge(json.load(fh)))
