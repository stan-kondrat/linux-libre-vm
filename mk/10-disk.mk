# ═════════════════════════════════════════════════════════════════════════════
# Phase 5.5 — Disk image + QEMU test
# ═════════════════════════════════════════════════════════════════════════════
#
# Disk image: raw ext4 (no MBR), kernel mounts via root=/dev/vda.
# Uses mke2fs -d to copy rootfs into the image in one pass.
# ═════════════════════════════════════════════════════════════════════════════

DISK_SIZE_MB := 256
DISK_DIR     := $(CURDIR)/disks

define DISK_IMAGE_RULE
disk-image-$(1):
	@echo "=== Creating disk image for $(1) ==="
	mkdir -p "$(DISK_DIR)"
	rm -f "$(DISK_DIR)/disk-$(1).img"
	dd if=/dev/zero of="$(DISK_DIR)/disk-$(1).img" bs=1M count=$(DISK_SIZE_MB) status=none
	# mke2fs with stable features (no metadata_csum/orphan_file to avoid corruption)
	mke2fs -F -q -t ext4 -b 4096 \
	  -O ^metadata_csum,^orphan_file,^flex_bg,^huge_file,^dir_nlink \
	  -d "$(ROOTFS_$(1))" \
	  "$(DISK_DIR)/disk-$(1).img" 2>/dev/null
	# Every file owned by root (the rootfs was staged by the build user)
	$(CURDIR)/mk/chown-root.sh "$(ROOTFS_$(1))" "$(DISK_DIR)/disk-$(1).img"
	# Run fsck to ensure clean filesystem
	e2fsck -fn "$(DISK_DIR)/disk-$(1).img" > /dev/null 2>&1 || true
	tune2fs -f -i 0 -c 0 "$(DISK_DIR)/disk-$(1).img" > /dev/null 2>&1 || true
	@echo "=== Disk image: $(DISK_DIR)/disk-$(1).img ==="
	du -sh "$(DISK_DIR)/disk-$(1).img"

disk-image-fsck-$(1):
	e2fsck -fvy "$(DISK_DIR)/disk-$(1).img"
endef

$(foreach t,$(TARGETS),$(eval $(call DISK_IMAGE_RULE,$(t))))

disk-image: $(addprefix disk-image-,$(BUILD_ARCHS))
	@echo "=== All disk images created ==="

disk-image-clean:
	rm -rf $(DISK_DIR)

# ═════════════════════════════════════════════════════════════════════════════
# QEMU boot
# ═════════════════════════════════════════════════════════════════════════════

# Foreground boot, console on this terminal (quit: Ctrl-a x). Devices and
# acceleration come from vm/qemu.sh (docs/qemu.md); BOOT_DIAG=1 adds boot.diag=1
define QEMU_RULE
qemu-$(1): $(call KERNEL_OUT,$(1)) $(DISK_DIR)/disk-$(1).img
	ARCH=$(1) KERNEL="$(call KERNEL_OUT,$(1))" DISK="$(DISK_DIR)/disk-$(1).img" \
	  APPEND="root=/dev/vda rw console=$(TTY_$(1))$$(if $$(BOOT_DIAG), boot.diag=1)" vm/qemu.sh run
endef

$(foreach t,$(TARGETS),$(eval $(call QEMU_RULE,$(t))))

ifneq ($(ARCH),)
disk-image: disk-image-$(ARCH)
qemu: qemu-$(ARCH)
else
qemu: qemu-x86_64
endif
