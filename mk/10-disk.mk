# ═════════════════════════════════════════════════════════════════════════════
# Phase 5.5 — Disk image + QEMU boot
# ═════════════════════════════════════════════════════════════════════════════
#
# Disk image: raw ext4 (no partition table), kernel mounts root=/dev/vda.
# mk/mkimage.sh builds it (also for the dev image, mk/14-toolchain.mk).
# ═════════════════════════════════════════════════════════════════════════════

DISK_SIZE_MB := 256
DISK_DIR     := $(CURDIR)/disks

define DISK_IMAGE_RULE
disk-image-$(1):
	$(CURDIR)/mk/mkimage.sh "$(ROOTFS_$(1))" "$(DISK_DIR)/disk-$(1).img" $(DISK_SIZE_MB)

disk-image-fsck-$(1):
	e2fsck -fvy "$(DISK_DIR)/disk-$(1).img"
endef

$(foreach t,$(TARGETS),$(eval $(call DISK_IMAGE_RULE,$(t))))

disk-image: $(addprefix disk-image-,$(BUILD_ARCHS))

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
