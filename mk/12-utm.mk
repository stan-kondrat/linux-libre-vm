# ═════════════════════════════════════════════════════════════════════════════
# UTM runner (macOS) — arm64 VM in UTM via AppleScript + utmctl, see docs/utm.md
# ═════════════════════════════════════════════════════════════════════════════
#
# Defaults point at the local build output; override with release files:
#   make utm-create UTM_KERNEL=linux-libre-vmlinuz-arm64 UTM_DISK=linux-libre-vm-arm64.img

UTM_NAME   ?= linux-libre-arm64
UTM_KERNEL ?= $(BUILD_DIR_arm64)/linux-libre/arch/arm64/boot/Image.gz
UTM_DISK   ?= $(DISK_DIR)/disk-arm64.img
UTM_VM     := NAME="$(UTM_NAME)" KERNEL="$(UTM_KERNEL)" DISK="$(UTM_DISK)" utm/utm-vm.sh

.PHONY: utm-create utm-recreate utm-start utm-console utm-stop utm-status utm-delete utm-test-alpine

utm-create utm-recreate utm-start utm-console utm-stop utm-status utm-delete:
	$(UTM_VM) $(@:utm-%=%)

utm-test-alpine:
	utm/alpine-test.sh
