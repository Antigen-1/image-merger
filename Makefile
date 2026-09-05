.PHONY: all build install run venv test integration demo fixtures clean

VENV := .venv
PY   := $(VENV)/bin/python

BUILD_DIR := .build
BOOT      := $(BUILD_DIR)/image-merger.boot
MAIN_SO   := $(BUILD_DIR)/im-main.so
MAIN_SS   := $(BUILD_DIR)/im-main.ss

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
run: build
	@test -n '$(CFG)' || { echo "usage: make run CFG=<config-file>  (e.g. CFG=examples/demo.cfg)" >&2; exit 2; }
	@bin/image-merger "$(CFG)"

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
