#!/bin/sh
# Relocatable launcher for the bundled image-merger.
#
# The bundle (bin/ + python/ + *.boot) can be copied to another machine; this
# script resolves every path relative to its own location and sets the
# environment the embedded Python needs:
#   LD_LIBRARY_PATH / LD_PRELOAD -> the bundled python/lib, so dlopen
#   ("libpython3.so") and Pillow's C extensions resolve against the bundled
#   interpreter (see README "Portability").
#
# Usage:  start-image-merger.sh <config-file>     (also --help, no args)
set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PYLIB="$DIR/python/lib"

if [ ! -x "$DIR/bin/image-merger" ]; then
    echo "start-image-merger: image-merger not found in $DIR/bin" >&2
    exit 2
fi

# python-build-standalone may only ship libpython3.<maj>.<min>.so(.1.0);
# make dist already creates the libpython3.so symlink when missing - keep a
# fallback for bundles assembled differently.
if [ ! -e "$PYLIB/libpython3.so" ]; then
    LP=$(ls "$PYLIB"/libpython3.*.so.1.0 2>/dev/null | head -1 || true)
    if [ -z "$LP" ]; then
        echo "start-image-merger: bundled python not found under $PYLIB" >&2
        exit 2
    fi
    ln -sf "$(basename "$LP")" "$PYLIB/libpython3.so"
fi

export LD_LIBRARY_PATH="$PYLIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
case ":${LD_PRELOAD:-}:" in
  *:libpython3*:*|*/libpython3*) ;;
  *)
    export LD_PRELOAD="$PYLIB/libpython3.so${LD_PRELOAD:+:$LD_PRELOAD}"
    ;;
esac

exec "$DIR/bin/image-merger" -q -- "$@"
