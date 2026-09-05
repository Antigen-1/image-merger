#!/usr/bin/env python3
"""End-to-end CLI + pixel tests for image-merger.

Drives bin/image-merger (the custom scheme-start boot) with a variety of
config files and checks, via Pillow, that canvas sizes, background, image
placement (fit/fill/stretch/none/exact), alignment, gaps, transparency and
row/column labels are all rendered correctly.  Also checks exit codes and
error messages.

Run:  make build && .venv/bin/python tests/test-integration.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin" / "image-merger"
assert BIN.exists(), f"missing {BIN} (run make build first?)"

CHECKS = 0
FAILS = 0


def check(cond, msg):
    global CHECKS, FAILS
    CHECKS += 1
    if not cond:
        FAILS += 1
        print(f"  FAIL: {msg}")
    else:
        print(f"  ok:   {msg}")


def run_cli(cfg_path, cwd=None):
    """Run the CLI; return (exitcode, stdout, stderr)."""
    env = dict(os.environ)
    proc = subprocess.run([str(BIN), str(cfg_path)], capture_output=True,
                          text=True, env=env, cwd=str(cwd) if cwd else None)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def solid(path, size, color):
    Image.new("RGB", size, color).save(path)


def halfsplit(path, size, left, right):
    """Size=(w,h); left half `left`, right half `right`."""
    img = Image.new("RGB", size)
    img.paste(left, (0, 0, size[0] // 2, size[1]))
    img.paste(right, (size[0] // 2, 0, size[0], size[1]))
    img.save(path)


def cfg(workdir, name, text, images):
    """Write a config; image paths inside the config are relative to the
    config file's directory, so pass them as plain file names."""
    text = text.replace("$D", str(workdir))
    for img, src in images.items():
        dst = workdir / img
        if src.resolve() != dst.resolve():
            shutil.copy(src, dst)
    p = workdir / name
    p.write_text(text, encoding="utf-8")
    return p


def section(title):
    print(f"\n== {title} ==")


def px(im, x, y):
    return tuple(im.getpixel((x, y))[:3])


def main():
    tmp = Path(tempfile.mkdtemp(prefix="im-test-", dir=str(ROOT / ".build")))
    print(f"workdir: {tmp}")

    # ------------------------------------------------------------------
    section("A. CLI usage / exit codes")
    # A1 help
    r = subprocess.run([str(BIN), "--help"], capture_output=True, text=True)
    check(r.returncode == 0, f"--help -> exit 0 (got {r.returncode})")
    check("usage: image-merger" in r.stdout, "--help prints usage")
    # A2 no args
    r = subprocess.run([str(BIN)], capture_output=True, text=True)
    check(r.returncode == 2, "no args -> exit 2")
    # A3 two args
    r = subprocess.run([str(BIN), "a.cfg", "b.cfg"], capture_output=True, text=True)
    check(r.returncode == 2, "two args -> exit 2")
    # A4 nonexistent config
    code, _, err = run_cli(tmp / "nope.cfg")
    check(code == 1 and "no such file" in err, f"missing config -> exit 1 + msg (got {code}: {err[:60]})")
    # A5 invalid s-exp config
    bad = tmp / "bad-sexp.cfg"
    bad.write_text("(image-merger (canvas", encoding="utf-8")
    code, _, err = run_cli(bad)
    check(code == 1, f"invalid s-exp -> exit 1 (got {code})")
    # A6 usage-error config (grid 0)
    bad2 = cfg(tmp, "bad-grid.cfg",
               '(image-merger (output "x.png") (canvas (grid 0 1) (cell-size 10 10)))', {})
    code, _, err = run_cli(bad2)
    check(code == 1, f"invalid grid -> exit 1 (got {code})")

    # ------------------------------------------------------------------
    section("B. basic grid: sizes, background, empty cells, gaps, margins")
    red = (230, 25, 75)
    blue = (67, 99, 216)  # #4363d8
    solid(tmp / "r.png", (90, 70), "#e6194b")
    solid(tmp / "b.png", (40, 40), "#4363d8")
    c = cfg(tmp, "basic.cfg", """(image-merger
  (output "$D/out-basic.png")
  (canvas (grid 2 3) (cell-size 100 80) (gap 10 5) (margin 4) (background "#1a1a2e"))
  (cell (row 0) (column 0) (image "r.png") (scale stretch))
  (cell (row 1) (column 2) (image "b.png") (scale fit)))""",
            {"r.png": tmp / "r.png", "b.png": tmp / "b.png"})
    code, out, err = run_cli(c)
    check(code == 0, f"basic run ok (got {code}: {err[:80]})")
    im = Image.open(tmp / "out-basic.png")
    bg = (26, 26, 46)  # #1a1a2e
    # width = 4 + 3*100 + 2*10 + 4 = 328 ; height = 4 + 2*80 + 5 + 4 = 173
    check(im.size == (328, 173), f"basic size (328,173) got {im.size}")
    check(px(im, 0, 0) == bg, "corner is margin background")
    # cell(0,0) stretched r.png
    check(px(im, 4 + 50, 4 + 40) == red, "cell(0,0) shows red (stretch)")
    # empty cell(0,1) shows background
    check(px(im, 4 + 100 + 10 + 50, 4 + 40) == bg, "empty cell(0,1) shows background")
    # cell(1,2): b.png 40x40 fit in 100x80 -> upscaled x2 to 80x80, centered
    # horizontally (ox=10), full height (oy=0)
    cx = 4 + 2 * (100 + 10)      # cell x = 224
    cy = 4 + (80 + 5)            # cell y = 89
    check(px(im, cx + 12, cy + 40) == blue, "cell(1,2) fit shows blue (80x80 upscale)")
    check(px(im, cx + 5, cy + 40) == bg, "cell(1,2) fit horizontal letterbox is bg")

    # ------------------------------------------------------------------
    section("C. scale modes & align (300x200 half-split image, 100x80 cell)")
    halfsplit(tmp / "h.png", (300, 200), red, blue)
    modes = """  (cell (row 0) (column 0) (image "h.png") (scale fit))
  (cell (row 0) (column 1) (image "h.png") (scale fill) (align right bottom))
  (cell (row 0) (column 2) (image "h.png") (scale stretch))
  (cell (row 0) (column 3) (image "h.png") (scale none))
  (cell (row 0) (column 4) (image "h.png") (scale (exact 40 40)) (align left top))"""
    c = cfg(tmp, "scales.cfg",
            f'(image-merger (output "$D/out-scales.png") '
            f'(canvas (grid 1 5) (cell-size 100 80) (gap 6)) {modes})',
            {"h.png": tmp / "h.png"})
    code, out, err = run_cli(c)
    check(code == 0, f"scales run ok (got {code}: {err[:80]})")
    im = Image.open(tmp / "out-scales.png")
    # fit: scale = min(100/300, 80/200) = 1/3 -> 100x67, centered: top offset 6
    # (x=20 maps to original x=60, safely on the red half)
    check(px(im, 20, 6 + 33) == red, "fit: mid row red on the left half")
    check(px(im, 90, 6 + 33) == blue, "fit: mid row blue on the right half")
    check(px(im, 50, 2) == (255, 255, 255), "fit: top letterbox white")
    # fill align right bottom: scaled 120x80; right align -> visible window x 20..120 of scaled image
    x1 = (100 + 6) + 90
    check(px(im, x1, 40) == blue, "fill+right shows blue near right edge")
    # stretch: split moves to 150/300*100=50
    x2 = (100 + 6) * 2 + 10
    check(px(im, x2, 40) == red, "stretch: left region red")
    check(px(im, x2 + 80, 40) == blue, "stretch: right region blue")
    # none: center crop window x 100..200 of original (split at 150)
    x3 = (100 + 6) * 3
    check(px(im, x3 + 10, 40) == red, "none: window left side red")
    check(px(im, x3 + 90, 40) == blue, "none: window right side blue")
    # exact 40x40 align left top: cell origin colored, outside white
    x4 = (100 + 6) * 4
    check(px(im, x4 + 5, 5) == red, "exact+lefttop: inside red")
    check(px(im, x4 + 45, 5) == (255, 255, 255), "exact+lefttop: outside white")

    # ------------------------------------------------------------------
    section("D. transparency (RGBA canvas + RGBA source)")
    rgba = Image.new("RGBA", (60, 40))
    rgba.paste((10, 200, 30, 255), (0, 0, 60, 40))
    rgba.save(tmp / "g.png")
    c = cfg(tmp, "t.cfg",
            '(image-merger (output "$D/out-t.png") '
            '(canvas (grid 1 2) (cell-size 60 40) (gap 5) (background "transparent")) '
            '(cell (row 0) (column 0) (image "g.png") (scale stretch)))',
            {"g.png": tmp / "g.png"})
    code, out, err = run_cli(c)
    check(code == 0, f"transparent run ok (got {code})")
    im = Image.open(tmp / "out-t.png")
    check(im.mode == "RGBA", f"RGBA output mode (got {im.mode})")
    check(im.getpixel((5, 20))[3] == 255, "image area opaque")
    check(px(im, 5, 20) == (10, 200, 30), "image colour preserved")
    check(im.getpixel((70, 20))[3] == 0, "empty cell fully transparent")
    check(im.getpixel((63, 20))[3] == 0, "gap transparent")

    # ------------------------------------------------------------------
    section("E. row/column labels")
    c = cfg(tmp, "labels.cfg", """(image-merger
  (output "$D/out-labels.png")
  (canvas (grid 2 2) (cell-size 60 50) (gap 4) (margin 5) (background "#ffffff"))
  (cell (row 1) (column 1) (image "b.png") (scale stretch))
  (row-labels (band 26) (start 1)
              (style (size 10) (color "#000000") (align right middle)))
  (column-labels (band 22)
                 (style (size 10) (color "#000000") (align center bottom))
                 (texts "A" "B")))""",
            {"b.png": tmp / "b.png"})
    code, out, err = run_cli(c)
    check(code == 0, f"labels run ok (got {code})")
    im = Image.open(tmp / "out-labels.png")
    # width = 5 + 26 + 2*60 + 4 + 5 = 160 ; height = 5 + 22 + 2*50 + 4 + 5 = 136
    check(im.size == (160, 136), f"labels size (160,136) got {im.size}")
    white = (255, 255, 255)
    row_band = [im.getpixel((x, y))[:3]
                for y in range(27, 27 + 50 + 54) for x in range(5, 31)]
    check(any(p != white for p in row_band), "row-label band contains text pixels")
    col_band = [im.getpixel((x, y))[:3]
                for x in range(31, 31 + 60 + 64) for y in range(5, 27)]
    check(any(p != white for p in col_band), "column-label band contains text pixels")

    # ------------------------------------------------------------------
    section("F. relative path resolution + run from another cwd")
    (tmp / "sub").mkdir(exist_ok=True)
    c = cfg(tmp / "sub", "rel.cfg",
            '(image-merger (output "sub-out.png") '
            '(canvas (grid 1 1) (cell-size 30 20)) '
            '(cell (row 0) (column 0) (image "b.png") (scale stretch)))',
            {"b.png": tmp / "b.png"})
    code, out, err = run_cli(c, cwd=tmp)
    check(code == 0, f"rel-path run ok (got {code})")
    check((tmp / "sub" / "sub-out.png").exists(), "output written next to config")

    # ------------------------------------------------------------------
    section("G. determinism + cache")
    im1 = (tmp / "out-basic.png").read_bytes()
    code, out, err = run_cli(tmp / "basic.cfg")
    im2 = (tmp / "out-basic.png").read_bytes()
    check(code == 0 and im1 == im2, "deterministic output")
    proc = subprocess.run(["make", "build"], capture_output=True, text=True, cwd=str(ROOT))
    check(proc.returncode == 0, "make build ok")
    proc = subprocess.run(["make", "-q", "build"], capture_output=True, text=True, cwd=str(ROOT))
    check(proc.returncode == 0, "make build is up-to-date (no-op)")

    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n==== {CHECKS} checks, {FAILS} failures ====")
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
