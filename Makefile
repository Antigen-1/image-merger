.PHONY: all build install run venv test demo fixtures clean

VENV := .venv
PY   := $(VENV)/bin/python

BUILD_DIR := .build
BOOT      := $(BUILD_DIR)/image-merger.boot

# Locate the boot file of the installed chez-python (a symlink to the Chez
# Scheme binary; its boot file sits next to the real binary).
CHZ_BOOT := $(shell dirname $(shell readlink -f $(shell command -v chez-python)))/chez-python.boot

# The Scheme libraries compiled into the cached boot.
IM_SLS := image-merger/config.sls image-merger/layout.sls image-merger/spec.sls

all: test

# --- Compile the Scheme code once into a cached chain boot ------------------
# image-merger.boot = chez-python.boot (embeds the Python startup program and
# the chez-python env bindings) + the compiled image-merger libraries.  `make
# run` then loads that boot instead of recompiling the libraries every time.
build: $(BOOT)

$(BOOT): $(IM_SLS) $(CHZ_BOOT)
	@mkdir -p $(BUILD_DIR)
	@echo "(make-boot-file \"$(abspath $(BOOT)).tmp\" '(\"scheme\") \
	       \"$(CHZ_BOOT)\" \
	       $(foreach f,$(IM_SLS),\"$(abspath $(f))\" ))" | scheme -q
	@mv "$(abspath $(BOOT)).tmp" "$(abspath $(BOOT))"
	@echo "built $(BOOT)"

# --- Run with a config file:  make run CFG=<config-file> --------------------
run: build
	@test -n '$(CFG)' || { echo "usage: make run CFG=<config-file>  (e.g. CFG=examples/demo.cfg)" >&2; exit 2; }
	@IMAGE_MERGER_BOOT="$(abspath $(BOOT))" bin/image-merger "$(CFG)"

# --- Python venv (Pillow backend) -----------------------------------------
venv: $(PY)

$(PY):
	python3 -m venv $(VENV)
	$(PY) -m pip install --disable-pip-version-check Pillow

# --- Scheme deps (chez-srfi for srfi :64 tests) ---------------------------
install:
	akku install

# --- Tests (pure Scheme libraries) ----------------------------------------
test: install
	eval $$(.akku/env -s) && \
	export CHEZSCHEMELIBDIRS="$$PWD:$$CHEZSCHEMELIBDIRS" && \
	scheme-script tests/test-config.sps && \
	scheme-script tests/test-layout.sps && \
	scheme-script tests/test-spec.sps

# --- Demo (end-to-end through chez-python + Pillow) -----------------------
fixtures: venv
	$(PY) examples/gen-fixtures.py

demo: fixtures
	bin/image-merger examples/demo.cfg

clean:
	rm -rf examples/img*.png examples/out.png $(BUILD_DIR)
