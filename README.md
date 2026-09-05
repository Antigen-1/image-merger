# image-merger

Stitch a set of images into a single picture according to an **s-expression
configuration file**. The grid geometry is computed in Chez Scheme; the actual
pixel work is delegated to Python's [Pillow](https://python-pillow.org/) through
the [chez-python](https://github.com/Antigen-1/chez-python) runtime.

## Requirements

- Chez Scheme with `chez-python` installed and on `$PATH`
  (the `chez-python` boot file that embeds the Python C API).
- Python 3 with `venv` (Pillow is installed into the project-local `.venv`).
- [akku](https://akkuscm.org/) for the dev/test dependency `chez-srfi`
  (`srfi :64`).

## Setup

```sh
make venv      # create .venv and install Pillow
make install   # akku install (fetches chez-srfi for the tests)
```

## Build & run

```sh
make build                          # compile the Scheme code once
make run CFG=examples/demo.cfg      # run with a config file
bin/image-merger <config-file>      # same, directly
```

- `make build` creates the cached **boot file** `.build/image-merger.boot`
  (only ~63 KB), built *by chez-python*: the compiled
  `(image-merger config/layout/spec/runner)` libraries plus our own whole
  program (`im-main.ss`) are linked **on top of chez-python as the sole base
  image** (`make-boot-file` allowed-libraries `'("chez-python")`). The
  chez-python libraries are therefore *not embedded*: at run time `scheme -b`
  loads our boot, then `chez-python.boot` (which itself loads `scheme.boot`)
  from the scheme boot search path — so chez-python must be installed where
  the scheme binary can find its boot. The boot is rebuilt automatically when
  the libraries or `im-main.ss` change.
- The boot carries its own **custom `scheme-start`** (a plain batch CLI, no
  chez-python REPL): it loads libpython3, initialises Python and hands the
  config file to the runner as a normal command-line argument. The wrapper
  loads the boot with `scheme -b`.
- `make run CFG=<config-file>` / `bin/image-merger <config-file>` therefore
  never recompile the Scheme libraries; `--help` prints usage, exit status is
  0/1/2 (ok / runtime error / usage error).

## Usage

Write a config file (see `examples/demo.cfg`) and run:

```sh
bin/image-merger <config-file>
make run CFG=<config-file>
bin/image-merger --help
```

Image and output paths inside the config are resolved **relative to the config
file's directory**.

> **Note on the Python runtime.** `bin/image-merger` preloads `libpython3.so`
> via `LD_PRELOAD` before starting the boot. The embedded Python interpreter
> is dlopened with local symbol visibility, which makes Python's C-extension
> modules (`math`, Pillow's `_imaging`, ...) fail to resolve the CPython API
> with "undefined symbol: PyFloat_Type" — preloading fixes that.

## Configuration format

The configuration is a single s-expression whose top-level form is
`(image-merger …)`. Image and output paths are resolved **relative to the
config file's directory**. Validation errors abort with exit status 1.

### Top-level structure

```scheme
(image-merger
  (output <string>)              ; required: output image path
  (canvas  <clause>*)            ; required: canvas / grid definition
  (cell    <clause>*)*           ; optional: one clause per filled cell
  (row-labels    <clause>*)      ; optional: row-number band on the left
  (column-labels <clause>*))     ; optional: column-number band on top
```

### `canvas` clauses

| clause | value | default |
|---|---|---|
| `(grid <rows> <cols>)` | positive integers | **required** |
| `(cell-size <w> <h>)` | positive integers | **required** (cell size in px) |
| `(gap <n>)` or `(gap <x> <y>)` | non-negative integers | `0` (x/y gaps may differ) |
| `(margin <n>)` or `(margin <top> <right> <bottom> <left>)` | non-negative integers | `0` |
| `(background <string>)` | colour name / `#rgb` / `#rrggbb` / `#rrggbbaa` / `"transparent"` | `"#ffffff"` (`transparent` yields an RGBA canvas) |

### `cell` clauses (one per filled cell)

```scheme
(cell (row <i>) (column <j>)      ; required: 0-based cell coordinates
      (image <path>)              ; required: image path (relative to config)
      (scale <mode>)              ; default fit
      (align <h> <v>))            ; default (center middle)
```

Only cells that should show an image need to be listed; every other cell is
left empty (the background shows through).

### Scale modes

| mode | behaviour |
|------|-----------|
| `fit` | scale to fit inside the cell, preserving aspect ratio (small images are scaled **up**) |
| `fill` | scale to cover the cell, cropping the overflow |
| `stretch` | stretch to the exact cell size (ignores aspect ratio) |
| `none` | keep the original size (parts outside the cell are cropped) |
| `(exact <w> <h>)` | scale to the given pixel size |

`align` (`h ∈ left\|center\|right`, `v ∈ top\|middle\|bottom`) decides where
the image sits inside its cell (for `fit`/`none`/`exact`) or which part is
cropped (for `fill`).

### Label clauses

```scheme
(row-labels                       ; column-labels is identical
  (band <n>)                    ; required: band thickness in px (added to canvas)
  (start <n>)                   ; default 0: first number shown
  (texts <string> ...)          ; optional: custom texts (may be shorter than
                                ; the row/column count); default: start, start+1, …
  (style
    (font <path-or-#f>)         ; default #f -> Pillow built-in bitmap font
    (size <n>)                  ; default 12
    (color <string>)            ; default "#000000"
    (align <h> <v>)))           ; default (center middle): text anchor in band
```

All `(style …)` items are optional and default independently. Row labels sit
in a band on the **left**, column labels in a band on the **top**.

### Geometry

```
canvas width  = margin-left  + row-label band + cols × cell-width
                + (cols-1) × gap-x + margin-right
canvas height = margin-top   + column-label band + rows × cell-height
                + (rows-1) × gap-y + margin-bottom
cell (i,j) top-left = (origin-x + j × (cell-width + gap-x),
                       origin-y + i × (cell-height + gap-y))
```

### Full example

```scheme
(image-merger
  (output "out.png")
  (canvas
    (background "#1a1a2e")     ; dark background
    (margin 20)                ; 20 px on all sides
    (gap 10 10)                ; 10 px x / y gaps
    (cell-size 160 120)        ; 160×120 per cell
    (grid 2 3))                ; 2 rows × 3 columns
  ;; row 0: all three cells filled
  (cell (row 0) (column 0) (image "img0.png") (scale fit))      ; contain
  (cell (row 0) (column 1) (image "img1.png") (scale fill))      ; cover + crop
  (cell (row 0) (column 2) (image "img2.png") (scale stretch))   ; distort
  ;; row 1: column 0 is intentionally omitted -> empty cell (background shows)
  (cell (row 1) (column 1) (image "img3.png") (scale none) (align right bottom))
  (cell (row 1) (column 2) (image "img4.png") (scale (exact 80 60)) (align left top))
  (row-labels                    ; row numbers 1, 2 on the left
    (band 28)
    (start 1)
    (style (size 14) (color "#ffffff") (align right middle)))
  (column-labels                 ; column names A, B, C on top
    (band 24)
    (style (size 14) (color "#ffffff") (align center bottom))
    (texts "A" "B" "C")))
```

Minimal configuration (everything else at its default):

```scheme
(image-merger
  (output "out.png")
  (canvas (grid 1 1) (cell-size 100 100))
  (cell (row 0) (column 0) (image "a.png")))
```

## Running the demo

```sh
make demo
# generates examples/img0..5.png and writes examples/out.png
```

## Tests

```sh
make test
```

- `tests/test-config.sps`, `tests/test-layout.sps`, `tests/test-spec.sps`
  exercise the pure Scheme libraries via `scheme-script` + `srfi :64`.
- The Python backend can be debugged standalone in the venv:

```sh
.venv/bin/python python/imagemerger.py spec.json
```

## Project layout

```
image-merger/
  Akku.manifest            ; akku package metadata (dev dep: chez-srfi)
  Makefile
  im-main.ss                ; boot program: custom scheme-start (batch CLI)
  image-merger/
    runner.sls               ; (image-merger runner)  Python-boundary orchestration
  bin/image-merger         ; wrapper: resolves paths, execs chez-python
  image-merger/
    config.sls             ; (image-merger config)  s-exp read + validation
    layout.sls             ; (image-merger layout)  grid geometry
    spec.sls               ; (image-merger spec)    layout -> FFI data contract
  python/
    imagemerger.py         ; Pillow backend (merge(spec))
  examples/
    demo.cfg
    gen-fixtures.py
  tests/
    test-*.sps
```


## Portability

Verified target: **Linux x86-64 (glibc)**.  Other platforms are best-effort:

- **Run time** needs only `scheme` on `$PATH`, the system `libpython3.so`
  (same minor as the venv), and the venv with Pillow (>= 9.1, for
  `Image.Resampling`).  chez-python itself is *not* needed at run time, but
  its `chez-python.boot` must be installed where the scheme binary looks for
  boots (the standard chez-python install layout: boot file next to the real
  scheme binary).  Tested with a minimal `PATH=/usr/bin:/bin` environment.
- **Build time** needs `chez-python` on `$PATH`, GNU make, `python3` and
  (for `make test`) akku.  Building from another directory works
  (`make -C <dir> build`).  No chez-python source tree or library path is
  required: the boot records chez-python as its base image by name
  (`allowed-libraries '("chez-python")`).
- **Python preload workaround**: `bin/image-merger` uses `LD_PRELOAD`
  (Linux/glibc only) so Python's C-extension modules can resolve the CPython
  API when the interpreter is embedded.  On macOS this needs an equivalent
  (e.g. `DYLD_INSERT_LIBRARIES` with the full `libpython3.dylib` path) and is
  untested; Windows is unsupported (shell wrapper, preload mechanism, path
  separators).
- **Path handling** is Unix-style ('/' separators, config-relative
  resolution); paths containing spaces work.  The venv must be created with a
  Python whose minor version matches the embedded libpython (the runner
  derives the site-packages path from the embedded version).

## License

MIT — see `LICENSE`.
