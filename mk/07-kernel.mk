# ═════════════════════════════════════════════════════════════════════════════
# Linux-libre kernel
# ═════════════════════════════════════════════════════════════════════════════
#
# Kernel builds are in-tree; sources are first copied from sources-patched/
# to sources-build/<target>/linux-libre/ via COPY_PKG (03-source-prep.mk).
# This keeps sources/linux-libre/ pristine.
#
# Per arch (00-vars.mk): KARCH_<a> (kernel ARCH=), KERNEL_TARGET_<a> (make
# target), KERNEL_IMAGE_<a> (its path), KERNEL_CONFIG_<a> (kernel-<a>.config).
# ═════════════════════════════════════════════════════════════════════════════

kernel: $(addprefix kernel-,$(BUILD_ARCHS))

install-kernel: $(addprefix install-kernel-,$(BUILD_ARCHS))

define KERNEL_RULES
$(eval $(call COPY_PKG,linux-libre,$(1)))

KMAKE_$(1) = $$(MAKE) -C "$(BUILD_DIR_$(1))/linux-libre" ARCH=$(KARCH_$(1)) CROSS_COMPILE=$(CROSS_$(1))

kernel-$(1): $(call KERNEL_OUT,$(1))

$(BUILD_DIR_$(1))/linux-libre/.built: $(BUILD_DIR_$(1))/linux-libre/.copied $(KERNEL_CONFIG_$(1))
	@echo "=== Configuring and building $(1) kernel ==="
	cp "$(KERNEL_CONFIG_$(1))" "$(BUILD_DIR_$(1))/linux-libre/.config"
	+$$(KMAKE_$(1)) olddefconfig
	+$$(KMAKE_$(1)) -j$$$$(nproc) $(KERNEL_TARGET_$(1))
	@touch "$$@"
	@ls -lh "$(call KERNEL_OUT,$(1))"

$(call KERNEL_OUT,$(1)): $(BUILD_DIR_$(1))/linux-libre/.built

kernel-reconfig-$(1):
	@echo "=== Reconfiguring $(1) kernel from scratch ==="
	$$(KMAKE_$(1)) tinyconfig && cp "$(BUILD_DIR_$(1))/linux-libre/.config" "$(KERNEL_CONFIG_$(1))"
	@echo "Now edit $(KERNEL_CONFIG_$(1)), then run 'make ARCH=$(1) kernel'"

install-kernel-$(1): kernel-$(1)
	mkdir -p "$(ROOTFS_$(1))/boot"
	cp "$(call KERNEL_OUT,$(1))" "$(ROOTFS_$(1))/boot/vmlinuz"
endef

$(foreach t,$(TARGETS),$(eval $(call KERNEL_RULES,$(t))))

ifneq ($(ARCH),)
kernel: kernel-$(ARCH)
install-kernel: install-kernel-$(ARCH)
kernel-reconfig: kernel-reconfig-$(ARCH)
endif
