# ═════════════════════════════════════════════════════════════════════════════
# Linux-libre kernel (dual-architecture)
# ═════════════════════════════════════════════════════════════════════════════
#
# Kernel builds are in-tree; sources are first copied from sources-patched/
# to sources-build/<target>/linux-libre/ via COPY_PKG (defined in 03-source-prep.mk).
# This keeps sources/linux-libre/ pristine.
# ═════════════════════════════════════════════════════════════════════════════

# Architecture mappings:
#   x86_64:  target=bzImage, cross=x86_64-linux-gnu-, config=kernel-x86_64.config
#   arm64:   target=Image.gz, cross=aarch64-linux-gnu-, config=kernel-arm64.config

# Kernel config paths (defined in 00-vars.mk)

KERNEL_TARGET_x86_64    := bzImage
KERNEL_CROSS_x86_64     := $(CROSS_x86_64)
KERNEL_OUT_x86_64       := $(BUILD_DIR_x86_64)/linux-libre/arch/x86/boot/bzImage
KERNEL_INSTALL_x86_64   := $(ROOTFS_x86_64)/boot/vmlinuz

KERNEL_TARGET_arm64     := Image.gz
KERNEL_CROSS_arm64      := $(CROSS_arm64)
KERNEL_OUT_arm64        := $(BUILD_DIR_arm64)/linux-libre/arch/arm64/boot/Image.gz
KERNEL_INSTALL_arm64    := $(ROOTFS_arm64)/boot/vmlinuz

# Copy linux-libre sources to build dirs (per-target)
$(eval $(call COPY_PKG,linux-libre,x86_64))
$(eval $(call COPY_PKG,linux-libre,arm64))

# Build all architectures
kernel: kernel-x86_64 kernel-arm64

# ── x86_64 ──────────────────────────────────────────────────────────────────

kernel-x86_64: $(KERNEL_OUT_x86_64)

# linux-libre is copied to BUILD_DIR via COPY_PKG (declared in 06-toolchain.mk).
# The .copied stamp ensures sources are prepared before building.
$(BUILD_DIR_x86_64)/linux-libre/.built: $(BUILD_DIR_x86_64)/linux-libre/.copied $(KERNEL_CONFIG_x86_64)
	@echo "=== Configuring and building x86_64 kernel ==="
	cp "$(KERNEL_CONFIG_x86_64)" "$(BUILD_DIR_x86_64)/linux-libre/.config"
	+$(MAKE) -C "$(BUILD_DIR_x86_64)/linux-libre" \
	  ARCH=x86_64 CROSS_COMPILE=$(KERNEL_CROSS_x86_64) \
	  olddefconfig
	+$(MAKE) -C "$(BUILD_DIR_x86_64)/linux-libre" \
	  ARCH=x86_64 CROSS_COMPILE=$(KERNEL_CROSS_x86_64) \
	  -j$$(nproc) $(KERNEL_TARGET_x86_64)
	@touch "$@"
	@echo "=== x86_64 kernel built: $(KERNEL_OUT_x86_64) ==="
	@ls -lh "$(KERNEL_OUT_x86_64)"

$(KERNEL_OUT_x86_64): $(BUILD_DIR_x86_64)/linux-libre/.built

kernel-reconfig-x86_64:
	@echo "=== Reconfiguring x86_64 kernel from scratch ==="
	cd "$(BUILD_DIR_x86_64)/linux-libre" && \
	  make ARCH=x86_64 CROSS_COMPILE=$(KERNEL_CROSS_x86_64) tinyconfig && \
	  cp .config "$(KERNEL_CONFIG_x86_64)"
	@echo "Now edit $(KERNEL_CONFIG_x86_64), then run 'make ARCH=x86_64 kernel'"

install-kernel-x86_64: kernel-x86_64
	@echo "=== Installing x86_64 kernel ==="
	mkdir -p "$(dir $(KERNEL_INSTALL_x86_64))"
	cp "$(KERNEL_OUT_x86_64)" "$(KERNEL_INSTALL_x86_64)"
	ls -lh "$(KERNEL_INSTALL_x86_64)"

# ── arm64 ───────────────────────────────────────────────────────────────────

kernel-arm64: $(KERNEL_OUT_arm64)

$(BUILD_DIR_arm64)/linux-libre/.built: $(BUILD_DIR_arm64)/linux-libre/.copied $(KERNEL_CONFIG_arm64)
	@echo "=== Configuring and building arm64 kernel ==="
	cp "$(KERNEL_CONFIG_arm64)" "$(BUILD_DIR_arm64)/linux-libre/.config"
	+$(MAKE) -C "$(BUILD_DIR_arm64)/linux-libre" \
	  ARCH=arm64 CROSS_COMPILE=$(KERNEL_CROSS_arm64) \
	  olddefconfig
	+$(MAKE) -C "$(BUILD_DIR_arm64)/linux-libre" \
	  ARCH=arm64 CROSS_COMPILE=$(KERNEL_CROSS_arm64) \
	  -j$$(nproc) $(KERNEL_TARGET_arm64)
	@touch "$@"
	@echo "=== arm64 kernel built: $(KERNEL_OUT_arm64) ==="
	@ls -lh "$(KERNEL_OUT_arm64)"

$(KERNEL_OUT_arm64): $(BUILD_DIR_arm64)/linux-libre/.built

kernel-reconfig-arm64:
	@echo "=== Reconfiguring arm64 kernel from scratch ==="
	cd "$(BUILD_DIR_arm64)/linux-libre" && \
	  make ARCH=arm64 CROSS_COMPILE=$(KERNEL_CROSS_arm64) tinyconfig && \
	  cp .config "$(KERNEL_CONFIG_arm64)"
	@echo "Now edit $(KERNEL_CONFIG_arm64), then run 'make ARCH=arm64 kernel'"

install-kernel-arm64: kernel-arm64
	@echo "=== Installing arm64 kernel ==="
	mkdir -p "$(dir $(KERNEL_INSTALL_arm64))"
	cp "$(KERNEL_OUT_arm64)" "$(KERNEL_INSTALL_arm64)"
	ls -lh "$(KERNEL_INSTALL_arm64)"

# ── Install all kernels ─────────────────────────────────────────────────────

install-kernel: install-kernel-x86_64 install-kernel-arm64
	@echo "=== All kernels installed ==="

# ═════════════════════════════════════════════════════════════════════════════
# ARCH-aware delegation targets (make ARCH=x86_64 kernel, etc.)
# ═════════════════════════════════════════════════════════════════════════════

ifneq ($(ARCH),)
kernel: kernel-$(ARCH)
install-kernel: install-kernel-$(ARCH)
kernel-reconfig: kernel-reconfig-$(ARCH)
endif
