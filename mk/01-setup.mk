# ═════════════════════════════════════════════════════════════════════════════
# Phony targets and setup (build-dirs, check-env)
# ═════════════════════════════════════════════════════════════════════════════

.PHONY: all clean distclean install help
.PHONY: check-env build-dirs fake-bin
.PHONY: kernel kernel-x86_64 kernel-arm64
.PHONY: install-kernel install-kernel-x86_64 install-kernel-arm64
.PHONY: kernel-reconfig-x86_64 kernel-reconfig-arm64
.PHONY: userland userland-x86_64 userland-arm64
.PHONY: install-all install-x86_64 install-arm64
.PHONY: strip-all prune-docs

# Per-package phony targets (generated via macros below)
# build-<pkg>, build-<pkg>-x86_64, build-<pkg>-arm64
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
	@which make >/dev/null || (echo "make not found" && exit 1)
	@which autoreconf >/dev/null || (echo "autoreconf not found" && exit 1)
	@$(foreach pkg,bash coreutils grep sed gawk findutils diffutils gzip tar vim \
	            iproute2 procps-ng util-linux runit dhcpcd,\
	  [ -d "$(SOURCES_DIR)/$(pkg)" ] || \
	    (echo "Missing submodule: $(pkg)" && exit 1);)
	@[ -d "$(GNULIB_DIR)" ] || (echo "Missing gnulib submodule" && exit 1)
	@echo "=== Environment OK ==="
	@echo "  Host:     $(HOST_TRIPLET)"
	@echo "  Targets:  $(TARGETS)"
