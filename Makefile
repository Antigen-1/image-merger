.PHONY: all build install run venv test integration demo fixtures clean

VENV := .venv
PY   := $(VENV)/bin/python

BUILD_DIR := .build
BOOT      := $(BUILD_DIR)/image-merger.boot
MAIN_SO   := $(BUILD_DIR)/im-main.so
MAIN_SS   := $(BUILD_DIR)/im-main.ss

# --- Relocatable distribution (make dist) ----------------------------------
# Bundles a self-contained, copy-to-any-machine directory:
#   .dist/image-merger/
#     bin/image-merger        copy of the Chez Scheme binary (boot auto-search
#                             by executable name), image-merger.boot,
#                             chez-python.boot, scheme.boot, petite.boot
#     python/                 python-build-standalone (self-contained CPython,
#                             Pillow preinstalled, backend module copied in)
# `make run` invokes bin/image-merger in that directory directly.
DIST_DIR  := .dist/image-merger
DIST_PY   := $(DIST_DIR)/python
DIST_BIN  := $(DIST_DIR)/bin
CACHE_DIR := .downloads
PYBS_VER  := 20260901
PYBS_PY   := 3.14.7
PYBS_TGZ  := $(CACHE_DIR)/python-build-standalone-$(PYBS_VER).tar.gz
# URL of the install_only glibc x86_64 build (override for mirrors).
PYBS_URL  := https://github.com/astral-sh/python-build-standalone/releases/download/$(PYBS_VER)/cpython-$(PYBS_PY)+$(PYBS_VER)-x86_64-unknown-linux-gnu-install_only.tar.gz
# Optional sha256 of $(PYBS_TGZ); leave empty to skip verification.
PYBS_SHA  :=

# Where the installed Chez Scheme keeps its kernel boot files: next to the
# real scheme binary (readlink -f resolves symlinks such as /usr/bin/scheme).
SCHEME_REAL := $(shell readlink -f $(shell command -v scheme))
SCHEME_DIR  := $(dir $(SCHEME_REAL))

$(PYBS_TGZ):
	@mkdir -p $(CACHE_DIR)
	@echo "downloading python-build-standalone $(PYBS_PY) ($(PYBS_VER)) ..."
	@wget --tries=3 -O "$@.tmp" "$(PYBS_URL)"
	@if [ -n "$(PYBS_SHA)" ]; then echo "$(PYBS_SHA)  $@.tmp" | sha256sum -c -; fi
	@mv "$@.tmp" "$@"

# Pillow + backend module installed into the standalone python
$(DIST_PY)/.pillow-stamp: $(PYBS_TGZ) python/imagemerger.py
	@rm -rf $(DIST_PY)
	@mkdir -p $(DIST_DIR)
	@tar -xzf $(PYBS_TGZ) -C $(DIST_DIR)
	@$(DIST_PY)/bin/python3.14 -m pip install --disable-pip-version-check --no-input Pillow
	@SITE=$$($(DIST_PY)/bin/python3.14 -c 'import sysconfig; print(sysconfig.get_path("purelib"))') && cp python/imagemerger.py "$$SITE/"
	@touch "$@"

# Boots + renamed scheme binary (auto-search chain: image-merger.boot ->
# chez-python.boot -> scheme.boot -> petite.boot, all in one directory)
$(DIST_BIN)/image-merger: $(BOOT) $(DIST_PY)/.pillow-stamp
	@mkdir -p $(DIST_BIN)
	@cp "$(SCHEME_REAL)" "$(DIST_BIN)/image-merger"
	@cp "$(SCHEME_DIR)petite.boot" "$(SCHEME_DIR)scheme.boot" $(DIST_BIN)/
	@cp "$(SCHEME_DIR)chez-python.boot" $(DIST_BIN)/
	@cp "$(BOOT)" "$(DIST_BIN)/image-merger.boot"
	@chmod +x "$(DIST_BIN)/image-merger"
	@# make dlopen("libpython3.so") resolve to the bundled python
	@if [ ! -e "$(DIST_PY)/lib/libpython3.so" ]; then 	  ln -s libpython3.so.1.0 "$(DIST_PY)/lib/libpython3.so"; fi
	@echo "dist ready: $(abspath $(DIST_DIR))"

.PHONY: dist
dist: $(DIST_BIN)/image-merger

# The installed chez-python (on $PATH) is used to *build* the boot file: its
# in-process library registry resolves the chez-python imports of our libraries
# during make-boot-file, so no chez-python source tree or library path is
# needed.

# The image-merger Scheme libraries compiled into the cached boot.
IM_SLS := image-merger/config.sls image-merger/layout.sls \
          image-merger/spec.sls image-merger/runner.sls

all: test

# --- Compile the Scheme code once into a cached boot ------------------------
# image-merger.boot = our own whole program (custom scheme-start) + the
# image-merger libraries, built ON TOP of chez-python as the sole base image:
# allowed-libraries '("chez-python") records the base by name, so the
# chez-python libraries are not embedded.  At run time `scheme -b` loads our
# boot and then chez-python.boot (which itself loads scheme.boot) from the
# scheme boot search path.  Running the boot starts our program directly: no
# chez-python REPL, no script loading - the config file is a plain argv
# argument.
build: $(BOOT)

# Our boot program: whole-program compile im-main.ss inside the build dir so
# all intermediate .wpo/.so files stay in .build/.
$(MAIN_SO): im-main.ss
	@mkdir -p $(BUILD_DIR)
	@cp im-main.ss $(MAIN_SS)
	@echo '(compile-imported-libraries #t)(generate-wpo-files #t)' \
	      '(compile-program "$(abspath $(MAIN_SS))")' | chez-python -q
	@echo '(compile-whole-program "$(abspath $(BUILD_DIR)/im-main.wpo)"' \
	      '"$(abspath $(MAIN_SO))" #t)' | chez-python -q

$(BOOT): $(IM_SLS) $(MAIN_SO)
	@mkdir -p $(BUILD_DIR)
	@echo "(make-boot-file \"$(abspath $(BOOT)).tmp\" '(\"chez-python\") \
	       $(foreach f,$(IM_SLS),\"$(abspath $(f))\" )\
	       \"$(abspath $(MAIN_SO))\" )" | chez-python -q
	@mv "$(abspath $(BOOT)).tmp" "$(abspath $(BOOT))"
	@echo "built $(BOOT)"

# --- Run with a config file:  make run CFG=<config-file> --------------------
# Uses the self-contained dist bundle (builds it on first use).
run: dist
	@test -n '$(CFG)' || { echo "usage: make run CFG=<config-file>  (e.g. CFG=examples/demo.cfg)" >&2; exit 2; }
	@LD_LIBRARY_PATH="$(abspath $(DIST_PY)/lib)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	  LD_PRELOAD="$(abspath $(DIST_PY)/lib/libpython3.so)$${LD_PRELOAD:+:$$LD_PRELOAD}" \
	  "$(abspath $(DIST_BIN)/image-merger)" -q -- "$(CFG)"

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

# --- Integration tests (CLI + pixel checks via the built boot) ------------
integration: build venv
	$(PY) tests/test-integration.py

# --- Demo (end-to-end through the cached boot + Pillow) -------------------
fixtures: venv
	$(PY) examples/gen-fixtures.py

demo: build fixtures
	bin/image-merger examples/demo.cfg

clean:
	rm -rf examples/img*.png examples/out.png $(BUILD_DIR)
