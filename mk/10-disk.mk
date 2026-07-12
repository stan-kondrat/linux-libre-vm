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
	# Run fsck to ensure clean filesystem
	e2fsck -fn "$(DISK_DIR)/disk-$(1).img" > /dev/null 2>&1 || true
	tune2fs -f -i 0 -c 0 "$(DISK_DIR)/disk-$(1).img" > /dev/null 2>&1 || true
	@echo "=== Disk image: $(DISK_DIR)/disk-$(1).img ==="
	du -sh "$(DISK_DIR)/disk-$(1).img"

disk-image-fsck-$(1):
	e2fsck -fvy "$(DISK_DIR)/disk-$(1).img"
endef

$(foreach t,$(TARGETS),$(eval $(call DISK_IMAGE_RULE,$(t))))

disk-image: disk-image-x86_64 disk-image-arm64
	@echo "=== All disk images created ==="

disk-image-clean:
	rm -rf $(DISK_DIR)

# ═════════════════════════════════════════════════════════════════════════════
# QEMU test
# ═════════════════════════════════════════════════════════════════════════════

KERNEL_x86_64 := $(BUILD_DIR_x86_64)/linux-libre/arch/x86/boot/bzImage
KERNEL_arm64  := $(BUILD_DIR_arm64)/linux-libre/arch/arm64/boot/Image.gz

QEMU_DISK_x86_64 := $(DISK_DIR)/disk-x86_64.img
QEMU_DISK_arm64  := $(DISK_DIR)/disk-arm64.img

qemu-x86_64: $(KERNEL_x86_64) $(QEMU_DISK_x86_64)
	qemu-system-x86_64 -m 256 -nographic \
	  -kernel $(KERNEL_x86_64) \
	  -drive file=$(QEMU_DISK_x86_64),format=raw,if=virtio \
	  -nic user,model=virtio-net-pci \
	  -append "root=/dev/vda rw console=ttyS0$(if $(BOOT_DIAG), boot.diag=1)"

qemu-arm64: $(KERNEL_arm64) $(QEMU_DISK_arm64)
	qemu-system-aarch64 -M virt -cpu cortex-a57 -m 256 -nographic \
	  -kernel $(KERNEL_arm64) \
	  -drive file=$(QEMU_DISK_arm64),format=raw,if=virtio \
	  -nic user,model=virtio-net-pci \
	  -append "root=/dev/vda rw console=ttyAMA0$(if $(BOOT_DIAG), boot.diag=1)"

ifneq ($(ARCH),)
disk-image: disk-image-$(ARCH)
qemu: qemu-$(ARCH)
else
qemu: qemu-x86_64
endif
