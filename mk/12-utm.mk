# ═════════════════════════════════════════════════════════════════════════════
# UTM runner (macOS) — arm64 VM in UTM via AppleScript + utmctl, see docs/utm.md
# ═════════════════════════════════════════════════════════════════════════════
#
# The VM lives in VM_DIR (bundle VM_DIR/<name>.utm, shared folder
# VM_DIR/shared, VM named after the directory). By default 'create' downloads
# the latest GitHub release (vm/release.sh); nothing has to be built:
#   make utm-create                         latest release
#   make utm-create VM_RELEASE=v1.0         a given release
#   make utm-create VM_SOURCE=local         this repo's build output
#   make utm-create UTM_KERNEL=Image.gz UTM_DISK=disk.img   any files
#   make utm-create VM_DIR=vm_tmp/vm2       another VM

VM_DIR     ?= vm_tmp/linux-libre-default
VM_SOURCE  ?= release
VM_RELEASE ?= latest
UTM_KERNEL ?=
UTM_DISK   ?=
UTM_VM     := VM_DIR="$(VM_DIR)" VM_SOURCE="$(VM_SOURCE)" VM_RELEASE="$(VM_RELEASE)" \
              KERNEL="$(UTM_KERNEL)" DISK="$(UTM_DISK)" vm/utm.sh

.PHONY: utm-create utm-recreate utm-start utm-console utm-stop utm-status utm-delete utm-list utm-test-alpine releases

utm-create utm-recreate utm-start utm-console utm-stop utm-status utm-delete utm-list:
	$(UTM_VM) $(@:utm-%=%)

utm-test-alpine:
	vm/alpine-test.sh

# Published releases (and which are cached in vm/cache/release/)
releases:
	vm/release.sh list
