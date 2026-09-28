# ═════════════════════════════════════════════════════════════════════════════
# Test targets
# ═════════════════════════════════════════════════════════════════════════════

test-dhcpcd-x86_64:
	@echo "=== DHCP test (x86_64) ==="
	timeout 10 $(MAKE) BOOT_DIAG=1 qemu-x86_64 2>&1 || true

test-dhcpcd-arm64:
	@echo "=== DHCP test (arm64) ==="
	timeout 10 $(MAKE) BOOT_DIAG=1 qemu-arm64 2>&1 || true

test-dhcpcd: $(addprefix test-dhcpcd-,$(BUILD_ARCHS))
	@echo "=== DHCP tests complete ==="

test-shutdown-x86_64:
	@echo "=== Shutdown test (x86_64) ==="
	timeout 6 $(MAKE) qemu-x86_64 2>&1 || true

test-shutdown-arm64:
	@echo "=== Shutdown test (arm64) ==="
	timeout 6 $(MAKE) qemu-arm64 2>&1 || true

test-shutdown: $(addprefix test-shutdown-,$(BUILD_ARCHS))
	@echo "=== Shutdown tests complete ==="

test: test-dhcpcd test-shutdown
	@echo "=== All tests complete ==="
