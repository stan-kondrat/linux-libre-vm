# ═════════════════════════════════════════════════════════════════════════════
# QEMU runner — background VM with plain QEMU (vm/qemu.sh), see docs/qemu.md
# ═════════════════════════════════════════════════════════════════════════════
#
# Same workflow as the utm-* targets, on any host with QEMU (e.g. inside a
# Linux build VM). Architecture: QEMU_ARCH, else ARCH, else arm64.
#   make qemu-start qemu-console        make QEMU_ARCH=x86_64 qemu-start
# For a one-off foreground boot use `make qemu-arm64` / `make qemu-x86_64`.

QEMU_ARCH   ?= $(or $(ARCH),arm64)
QEMU_NAME   ?= linux-libre-$(QEMU_ARCH)
QEMU_KERNEL ?= $(KERNEL_$(QEMU_ARCH))
QEMU_IMAGE  ?= $(QEMU_DISK_$(QEMU_ARCH))
QEMU_VM     := ARCH="$(QEMU_ARCH)" NAME="$(QEMU_NAME)" KERNEL="$(QEMU_KERNEL)" DISK="$(QEMU_IMAGE)" vm/qemu.sh

.PHONY: qemu-start qemu-console qemu-stop qemu-status qemu-delete qemu-test-alpine

qemu-start qemu-console qemu-stop qemu-status qemu-delete:
	$(QEMU_VM) $(@:qemu-%=%)

qemu-test-alpine:
	RUNNER=qemu vm/alpine-test.sh
