# ═════════════════════════════════════════════════════════════════════════════
# Source preparation: copy sources/ → sources-patched/, apply patches
# ═════════════════════════════════════════════════════════════════════════════

# PATCH_SRC_PKG(pkg) — copies sources/<pkg> to sources-patched/<pkg> and applies patches once
# Stamp: sources-patched/<pkg>/.patched
# All build targets depend on this stamp file.
define PATCH_SRC_PKG
$$(SOURCES_PATCHED_DIR)/$(1)/.patched:
	@mkdir -p "$$(SOURCES_PATCHED_DIR)"
	@echo "=== Copying $(1) sources to sources-patched ==="
	rm -rf "$$(SOURCES_PATCHED_DIR)/$(1)"
	mkdir -p "$$(SOURCES_PATCHED_DIR)/$(1)"
	rsync -a --exclude=.git "$$(SOURCES_DIR)/$(1)/" "$$(SOURCES_PATCHED_DIR)/$(1)/"
	@if [ -d "$$(SOURCES_PATCHES_DIR)/$(1)" ]; then \
		patches=$$(wildcard $$(SOURCES_PATCHES_DIR)/$(1)/*.patch); \
		if [ -n "$$$$patches" ]; then \
			echo "=== Applying patches for $(1) ==="; \
			cd "$$(SOURCES_PATCHED_DIR)/$(1)"; \
			for p in $$$$patches; do \
				echo "  $$(notdir $$$$p)..."; \
				patch -p1 < "$$$$p"; \
			done; \
		fi; \
	fi
	@touch "$$@"
endef

# COPY_PKG(pkg, target) — copies sources-patched/<pkg> to sources-build/<target>/<pkg> (build dir)
# Used for packages that need per-target source modifications (gnulib bootstrap, autoreconf, etc.).
# For simple packages, sources-patched/ is used directly as srcdir via --srcdir or ./configure.
define COPY_PKG
$$(BUILD_DIR_$(2))/$(1)/.copied: $$(SOURCES_PATCHED_DIR)/$(1)/.patched
	@echo "=== Copying $(1) sources to $(2) build dir ==="
	rm -rf "$$(BUILD_DIR_$(2))/$(1)"
	mkdir -p "$$(BUILD_DIR_$(2))/$(1)"
	rsync -a --exclude=.git "$$(SOURCES_PATCHED_DIR)/$(1)/" "$$(BUILD_DIR_$(2))/$(1)/"
	@touch "$$@"
endef

# ── Per-package patch targets (declared once, not per-target) ──────────────

PATCHED_PACKAGES := coreutils grep sed findutils diffutils gzip tar bash gawk \
                    procps-ng util-linux vim iproute2 runit dhcpcd \
                    binutils gcc glibc linux-libre

$(foreach p,$(PATCHED_PACKAGES),$(eval $(call PATCH_SRC_PKG,$(p))))

# ── Source preparation aggregate targets ───────────────────────────────────

# Macro: one prepare-sources-<pkg> target per package
define PREPARE_SOURCES_RULE
.PHONY: prepare-sources-$(1)
prepare-sources-$(1): $$(SOURCES_PATCHED_DIR)/$(1)/.patched
	@echo "=== $(1) prepared (sources-patched/$(1)) ==="
endef

$(foreach p,$(PATCHED_PACKAGES),$(eval $(call PREPARE_SOURCES_RULE,$(p))))

.PHONY: prepare-sources
prepare-sources: $(addprefix prepare-sources-,$(PATCHED_PACKAGES))
	@echo "=== All sources prepared in $(SOURCES_PATCHED_DIR) ==="
	@echo "  Packages: $(PATCHED_PACKAGES)"
