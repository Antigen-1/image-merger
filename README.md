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

- `make build` creates the cached **boot file** `.build/image-merger.boot`,
  built *by chez-python*: the installed `chez-python.boot` acts as the chain
  base (it supplies the chez-python libraries) and the compiled
  `(image-merger config/layout/spec/runner)` libraries plus our own whole
  program (`im-main.ss`) are linked on top. The boot is rebuilt automatically
  when the libraries or the installed chez-python boot change.
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

```scheme
(image-merger
  (output "out.png")

  (canvas
    (background "#1a1a2e")   ; color name / "#rrggbb" / "transparent"
    (margin 20)              ; (margin <n>) or (margin <top> <right> <bottom> <left>)
    (gap 10 10)              ; (gap <n>) or (gap <x> <y>)
    (cell-size 160 120)      ; width height of each cell
    (grid 2 3))              ; (rows columns)

  ;; Only cells that should show an image need to be listed; every other cell
  ;; is left empty (the background shows through).
  (cell (row 0) (column 0) (image "img0.png")
        (scale fit)                  ; fit | fill | stretch | none | (exact <w> <h>)
        (align center middle))       ; left|center|right  ×  top|middle|bottom

  (cell (row 1) (column 2) (image "img4.png")
        (scale (exact 80 60)) (align left top))

  ;; Optional row/column number labels.
  (row-labels
    (band 28)                ; label band thickness in pixels
    (start 1)                ; first row number
    (style (size 14) (color "#ffffff") (align right middle)))
  (column-labels
    (band 24)
    (style (size 14) (color "#ffffff") (align center bottom))
    (texts "A" "B" "C")))   ; optional custom texts (default: column numbers)
```

### Scale modes

| mode | behaviour |
|------|-----------|
| `fit` | scale to fit inside the cell, preserving aspect ratio |
| `fill` | scale to cover the cell, cropping the overflow |
| `stretch` | stretch to the exact cell size (ignores aspect ratio) |
| `none` | keep the original size |
| `(exact <w> <h>)` | scale to the given pixel size |

`align` decides where the image sits inside its cell (or, for `fill`, which
part is cropped).

### Label style

Inside `(style ...)`, all of `(font <path>)`, `(size <n>)`, `(color <color>)`
and `(align <h> <v>)` are optional. `font` defaults to Pillow's built-in
bitmap font; give a TTF/OTF path for nicer labels.

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

## License

MIT — see `LICENSE`.
