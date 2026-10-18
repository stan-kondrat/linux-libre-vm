# ═════════════════════════════════════════════════════════════════════════════
# Test targets: boot the built image under QEMU and check it
# (scripts/smoke-test.sh — the same checks CI runs). Each fails on a failure.
#   make test               base images of all BUILD_ARCHS
#   make test-<arch>        one base image
#   make test-dev           the dev image of this host (mk/14-toolchain.mk)
# ═════════════════════════════════════════════════════════════════════════════

.PHONY: test test-dev $(addprefix test-,$(TARGETS))

define TEST_RULE
test-$(1):
	ARCH=$(1) KERNEL="$(call KERNEL_OUT,$(1))" DISK="$(DISK_DIR)/disk-$(1).img" scripts/smoke-test.sh
endef

$(foreach t,$(TARGETS),$(eval $(call TEST_RULE,$(t))))

test: $(addprefix test-,$(BUILD_ARCHS))

test-dev:
	ARCH=$(TC_ARCH) KERNEL="$(call KERNEL_OUT,$(TC_ARCH))" DISK="$(DISK_DIR)/disk-$(TC_ARCH)-dev.img" \
	  PROFILE=dev scripts/smoke-test.sh
