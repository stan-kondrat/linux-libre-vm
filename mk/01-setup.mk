# ═════════════════════════════════════════════════════════════════════════════
# Phony targets and setup (build-dirs, check-env)
# ═════════════════════════════════════════════════════════════════════════════

.PHONY: all clean distclean install help
.PHONY: check-env build-dirs
.PHONY: kernel kernel-x86_64 kernel-arm64
.PHONY: install-kernel install-kernel-x86_64 install-kernel-arm64
.PHONY: kernel-reconfig-x86_64 kernel-reconfig-arm64
.PHONY: userland userland-x86_64 userland-arm64
.PHONY: install-all install-x86_64 install-arm64
.PHONY: strip-all prune-docs

# ARCH-aware targets (users: make ARCH=x86_64 build-coreutils)
# build-<pkg>, install-<pkg> — delegate to build-<pkg>-$(ARCH) when ARCH is set

# Internal per-package per-arch targets (generated via macros below)
# build-<pkg>-x86_64, build-<pkg>-arm64
# install-<pkg>-x86_64, install-<pkg>-arm64

.DELETE_ON_ERROR:

# ── Directory creation ─────────────────────────────────────────────────────

build-dirs:
	@echo "=== Creating directories ==="
	@for t in $(TARGETS); do \
	  mkdir -p "$(BUILD_DIR_x86_64)" "$(BUILD_DIR_arm64)" \
	           "$(ROOTFS_x86_64)" "$(ROOTFS_arm64)" \
	           "$(SOURCES_PATCHED_DIR)" "$(SOURCES_PATCHES_DIR)" "$(FAKE_BIN)"; \
	done

# ── Environment check ──────────────────────────────────────────────────────

check-env: build-dirs
	@echo "=== Checking host tools ==="
	@which make >/dev/null || (echo "ERROR: make not found" && exit 1)
	@which autoreconf >/dev/null || (echo "ERROR: autoreconf not found" && exit 1)
	@which rsync >/dev/null 2>&1 || (echo "WARNING: rsync not found; using cp instead" && \
	  printf '#!/bin/sh\ncp -a "$$@"\n' > "$(FAKE_BIN)/rsync" && chmod +x "$(FAKE_BIN)/rsync")
	@echo ""
	@echo "=== Checking x86_64 toolchain ==="
ifeq ($(CROSS_x86_64),)
	@which gcc >/dev/null 2>&1 && echo "  gcc: $$(gcc --version | head -1)" || \
	  (echo "ERROR: gcc not found" && exit 1)
	@echo "  (native — host x86_64)"
else
	@which $(CROSS_x86_64)gcc >/dev/null 2>&1 && \
	  echo "  $(CROSS_x86_64)gcc: $$($(CROSS_x86_64)gcc --version | head -1)" || \
	  (echo "ERROR: $(CROSS_x86_64)gcc not found — install cross-x86_64-linux-gnu" && exit 1)
	@test -d "$(SYSROOT_x86_64)/usr/include" && \
	  echo "  sysroot: $(SYSROOT_x86_64)" || \
	  (echo "ERROR: sysroot $(SYSROOT_x86_64)/usr/include not found" && exit 1)
endif
	@echo ""
	@echo "=== Checking arm64 toolchain ==="
ifeq ($(CROSS_arm64),)
	@which gcc >/dev/null 2>&1 && echo "  gcc: $$(gcc --version | head -1)" || \
	  (echo "ERROR: gcc not found" && exit 1)
	@echo "  (native — host aarch64)"
else
	@which $(CROSS_arm64)gcc >/dev/null 2>&1 && \
	  echo "  $(CROSS_arm64)gcc: $$($(CROSS_arm64)gcc --version | head -1)" || \
	  (echo "ERROR: $(CROSS_arm64)gcc not found — install cross-aarch64-linux-gnu" && exit 1)
	@test -d "$(SYSROOT_arm64)/usr/include" && \
	  echo "  sysroot: $(SYSROOT_arm64)" || \
	  (echo "ERROR: sysroot $(SYSROOT_arm64)/usr/include not found" && exit 1)
endif
	@echo ""
	@echo "=== Checking submodules ==="
	@$(foreach pkg,bash coreutils grep sed gawk findutils diffutils gzip tar vim \
	            iproute2 procps-ng util-linux runit dhcpcd,\
	  [ -d "$(SOURCES_DIR)/$(pkg)" ] && echo "  $(pkg): OK" || \
	    (echo "  $(pkg): MISSING — run 'git submodule update --init'" && exit 1);)
	@[ -d "$(GNULIB_DIR)" ] && echo "  gnulib: OK" || \
	  (echo "  gnulib: MISSING — run 'git submodule update --init --recursive'" && exit 1)
	@echo ""
	@echo "=== Environment OK ==="
	@echo "  Host:     $(HOST_TRIPLET)"
	@echo "  Targets:  $(TARGETS)"
	@echo "  Config:"
ifeq ($(CROSS_x86_64),)
	@echo "    x86_64:  native (host gcc)"
else
	@echo "    x86_64:  cross ($(CROSS_x86_64)gcc, sysroot: $(SYSROOT_x86_64))"
endif
ifeq ($(CROSS_arm64),)
	@echo "    arm64:   native (host gcc)"
else
	@echo "    arm64:   cross ($(CROSS_arm64)gcc, sysroot: $(SYSROOT_arm64))"
endif
