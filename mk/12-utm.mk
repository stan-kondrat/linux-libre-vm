# ═════════════════════════════════════════════════════════════════════════════
# UTM runner (macOS) — arm64 VM in UTM via AppleScript + utmctl, see docs/utm.md
# ═════════════════════════════════════════════════════════════════════════════
#
# The VM lives in VM_DIR (bundle VM_DIR/<name>.utm, shared folder
# VM_DIR/shared, VM named after the directory). Defaults point at the local
# build output; override with release files or another VM directory:
#   make utm-create UTM_KERNEL=linux-libre-vmlinuz-arm64 UTM_DISK=linux-libre-vm-arm64.img
#   make utm-create VM_DIR=vm_tmp/vm2

VM_DIR     ?= vm_tmp/linux-libre-default
UTM_KERNEL ?= $(BUILD_DIR_arm64)/linux-libre/arch/arm64/boot/Image.gz
UTM_DISK   ?= $(DISK_DIR)/disk-arm64.img
UTM_VM     := VM_DIR="$(VM_DIR)" KERNEL="$(UTM_KERNEL)" DISK="$(UTM_DISK)" vm/utm.sh

.PHONY: utm-create utm-recreate utm-start utm-console utm-stop utm-status utm-delete utm-list utm-test-alpine

utm-create utm-recreate utm-start utm-console utm-stop utm-status utm-delete utm-list:
	$(UTM_VM) $(@:utm-%=%)

utm-test-alpine:
	vm/alpine-test.sh
