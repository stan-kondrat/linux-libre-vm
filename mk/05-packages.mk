# ═════════════════════════════════════════════════════════════════════════════
# Per-target package declarations, aliases, and aggregate targets
# ═════════════════════════════════════════════════════════════════════════════

# ── Per-target package declarations ────────────────────────────────────────

$(foreach t,$(TARGETS),$(eval $(call GIT_GNULIB_RULES_PKG,coreutils,$(t),9.6)))
$(foreach t,$(TARGETS),$(eval $(call GIT_GNULIB_RULES_PKG,grep,$(t),3.11)))
$(foreach t,$(TARGETS),$(eval $(call GIT_GNULIB_RULES_PKG,sed,$(t),4.9)))
$(foreach t,$(TARGETS),$(eval $(call GIT_GNULIB_RULES_PKG,findutils,$(t),4.10.0)))
$(foreach t,$(TARGETS),$(eval $(call GIT_GNULIB_RULES_PKG,diffutils,$(t),3.10)))
$(foreach t,$(TARGETS),$(eval $(call GIT_GNULIB_RULES_PKG,gzip,$(t),1.13)))

$(foreach t,$(TARGETS),$(eval $(call TAR_BUILD_RULES,$(t))))

$(foreach t,$(TARGETS),$(eval $(call GIT_AUTORECONF_RULES_PKG,procps-ng,$(t),4.0.5)))
$(foreach t,$(TARGETS),$(eval $(call GIT_AUTORECONF_RULES_PKG,util-linux,$(t),2.40.4)))

$(foreach t,$(TARGETS),$(eval $(call GIT_CONFIGURE_RULES_PKG,bash,$(t))))
$(foreach t,$(TARGETS),$(eval $(call GIT_CONFIGURE_RULES_PKG,gawk,$(t))))

$(foreach t,$(TARGETS),$(eval $(call IPROUTE2_BUILD_RULES,$(t))))
$(foreach t,$(TARGETS),$(eval $(call DHCPCD_BUILD_RULES,$(t))))
$(foreach t,$(TARGETS),$(eval $(call VIM_BUILD_RULES,$(t))))
$(foreach t,$(TARGETS),$(eval $(call RUNIT_BUILD_RULES,$(t))))
$(foreach t,$(TARGETS),$(eval $(call OPENSSL_BUILD_RULES,$(t))))
$(foreach t,$(TARGETS),$(eval $(call OPENSSH_BUILD_RULES,$(t))))


# ═════════════════════════════════════════════════════════════════════════════
# Aliases and aggregates (USERLAND_PKGS: mk/00-vars.mk)
# ═════════════════════════════════════════════════════════════════════════════

# <pkg>: build it for all targets
$(foreach p,$(USERLAND_PKGS),$(eval $(p): $(addprefix build-$(p)-,$(TARGETS))))

$(foreach a,$(TARGETS),$(eval userland-$(a): $(addprefix build-,$(addsuffix -$(a),$(USERLAND_PKGS)))))

userland: $(addprefix userland-,$(BUILD_ARCHS))
	@echo "=== All userland packages built (all targets) ==="

all: check-env build-dirs userland

build: check-env build-dirs userland kernel
	@echo "=== All packages + kernel built for all targets ==="
	@echo "  Run 'make install' to install all, or 'make ARCH=x86_64 install' / 'make ARCH=arm64 install'"

# ═════════════════════════════════════════════════════════════════════════════
# install-<arch>: packages → libraries → strip → prune → /bin → init
# ═════════════════════════════════════════════════════════════════════════════

define INSTALL_ARCH
install-$(1): userland-$(1)
	@echo "=== Installing to $(ROOTFS_$(1)) ==="
	mkdir -p "$(ROOTFS_$(1))"
	for pkg in $(USERLAND_PKGS); do \
	  $$(MAKE) install-$$$$pkg-$(1) || exit 1; \
	done
	$$(MAKE) install-libs-$(1)
	$$(MAKE) strip-all-$(1) 2>/dev/null || true
	$$(MAKE) prune-docs-$(1) 2>/dev/null || true
	$$(MAKE) consolidate-bin-$(1)
	$$(MAKE) install-init-$(1)
	@echo "=== Install complete ($(1)) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_ARCH,$(t))))

install-all: $(addprefix install-,$(BUILD_ARCHS))
	@echo "=== All installs complete ==="

install: install-all
	@echo "=== All installs complete ==="

# ═════════════════════════════════════════════════════════════════════════════
# Copy shared libraries into rootfs
# ═════════════════════════════════════════════════════════════════════════════
# The dynamic linker (LDSO_<a>) and the libraries in INSTALL_LIBS_<a> come
# from the cross sysroot, or from the host for native builds; copy-libs.sh
# then adds everything else the binaries link against (DT_NEEDED,
# recursively): native builds pick up host libraries such as ncurses, gmp or
# pam.

INSTALL_LIBS_x86_64 := libc.so.6 libm.so.6 libpthread.so.0 librt.so.1 \
    libdl.so.2 libutil.so.1 libresolv.so.2 libcrypt.so.2 \
    libnss_files.so.2 libnss_dns.so.2 \
    libncursesw.so.6 libgmp.so.10 libmpfr.so.6
INSTALL_LIBS_arm64  := libc.so.6 libm.so.6 libpthread.so.0 librt.so.1 \
    libdl.so.2 libutil.so.1 libresolv.so.2

LIB_DIRS = $(foreach d,usr/lib usr/lib64 usr/lib/$(MULTIARCH_$(1)) lib lib64 lib/$(MULTIARCH_$(1)),$(SYSROOT_$(1))/$(d))

define INSTALL_LIBS
install-libs-$(1):
	@echo "=== Installing shared libraries ($(1)) ==="
	mkdir -p "$(ROOTFS_$(1))/lib" "$(ROOTFS_$(1))/lib64"
	for d in $(call LIB_DIRS,$(1)); do \
	  [ -e "$$$$d/$(notdir $(LDSO_$(1)))" ] && { cp -L "$$$$d/$(notdir $(LDSO_$(1)))" "$(ROOTFS_$(1))$(LDSO_$(1))"; break; }; \
	done; \
	[ -e "$(ROOTFS_$(1))$(LDSO_$(1))" ] || { echo "ERROR: $(notdir $(LDSO_$(1))) not found"; exit 1; }
	# A dynamic linker in /lib is also reachable as /lib64/<name>
	$(if $(filter /lib/,$(dir $(LDSO_$(1)))),ln -sf $(LDSO_$(1)) "$(ROOTFS_$(1))/lib64/")
	for lib in $(INSTALL_LIBS_$(1)); do \
	  for d in $(call LIB_DIRS,$(1)); do \
	    [ -e "$$$$d/$$$$lib" ] && { cp -L "$$$$d/$$$$lib" "$(ROOTFS_$(1))/lib/"; break; }; \
	  done; \
	done
	$(CURDIR)/mk/copy-libs.sh "$(ROOTFS_$(1))" $(CROSS_$(1))readelf $(call LIB_DIRS,$(1))
	# ld-linux may search /usr/lib64/, not /lib/ — symlink so it finds our libs
	ln -sf /lib "$(ROOTFS_$(1))/usr/lib64" 2>/dev/null || true
	@echo "=== Shared libraries installed ==="
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_LIBS,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# Per-target post-install
# ═════════════════════════════════════════════════════════════════════════════

define STRIP_ALL
strip-all-$(1):
ifneq ($(STRIP),0)
	@echo "=== Stripping $(1) binaries ==="
	find "$(ROOTFS_$(1))"/bin "$(ROOTFS_$(1))"/sbin \
	     "$(ROOTFS_$(1))"/usr/bin "$(ROOTFS_$(1))"/usr/sbin \
	     -type f -exec $(CROSS_$(1))strip -s {} \; 2>/dev/null || true
	find "$(ROOTFS_$(1))"/lib "$(ROOTFS_$(1))"/usr/lib "$(ROOTFS_$(1))"/usr/libexec \
	     -type f -name '*.so*' -exec $(CROSS_$(1))strip --strip-unneeded {} \; 2>/dev/null || true
endif
endef

$(foreach t,$(TARGETS),$(eval $(call STRIP_ALL,$(t))))

# Documentation, locales, desktop files, and the parts of the vim runtime
# not needed (keep syntax/, indent/, ftplugin/, autoload/, colors/, plugin/)
PRUNE_DOCS_PATHS := usr/share/doc usr/share/man usr/share/info usr/share/locale \
    var/cache usr/share/applications usr/share/icons \
    $(addprefix usr/share/vim/vim92/,doc tutor spell print macros tools pack colors/lists colors/tools import)

define PRUNE_DOCS
prune-docs-$(1):
	@echo "=== Pruning docs ($(1)) ==="
	-cd "$(ROOTFS_$(1))" && rm -rf $(PRUNE_DOCS_PATHS) tmp/*
endef

$(foreach t,$(TARGETS),$(eval $(call PRUNE_DOCS,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# Binary consolidation — move all binaries to /bin
# ═════════════════════════════════════════════════════════════════════════════

define CONSOLIDATE_BIN
consolidate-bin-$(1):
	@echo "=== Consolidating binaries to /bin ($(1)) ==="
	# Move /usr/bin/* to /bin/*
	if [ -d "$(ROOTFS_$(1))/usr/bin" ]; then \
	  mv "$(ROOTFS_$(1))/usr/bin/"* "$(ROOTFS_$(1))/bin/" 2>/dev/null || true; \
	  rmdir "$(ROOTFS_$(1))/usr/bin" 2>/dev/null || true; \
	fi
	# Move /usr/sbin/* to /bin/*
	if [ -d "$(ROOTFS_$(1))/usr/sbin" ]; then \
	  mv "$(ROOTFS_$(1))/usr/sbin/"* "$(ROOTFS_$(1))/bin/" 2>/dev/null || true; \
	  rmdir "$(ROOTFS_$(1))/usr/sbin" 2>/dev/null || true; \
	fi
	# Move real programs out of /sbin (iproute2: ip, ss; util-linux: agetty,
	# fdisk, ...) before recreating it; only move files not already in /bin
	if [ -d "$(ROOTFS_$(1))/sbin" ]; then \
	  for f in "$(ROOTFS_$(1))/sbin/"*; do \
	    [ -e "$$$$f" ] || [ -L "$$$$f" ] || continue; \
	    b=$$$$(basename "$$$$f"); \
	    [ -e "$(ROOTFS_$(1))/bin/$$$$b" ] || mv "$$$$f" "$(ROOTFS_$(1))/bin/"; \
	  done; \
	fi
	# /sbin/ only contains symlinks to /bin/ — recreate fresh to avoid loop
	rm -rf "$(ROOTFS_$(1))/sbin"
	mkdir -p "$(ROOTFS_$(1))/sbin"
	ln -sf /bin/runit-init "$(ROOTFS_$(1))/sbin/init"   # kernel looks for /sbin/init
	ln -sf /bin/runit      "$(ROOTFS_$(1))/sbin/runit"   # runit-init looks for /sbin/runit
	# Create /bin/sh -> /bin/bash symlink (scripts use #!/bin/sh)
	ln -sf /bin/bash "$(ROOTFS_$(1))/bin/sh" 2>/dev/null || true
	@echo "=== Binaries consolidated ($(1)) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call CONSOLIDATE_BIN,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# ARCH-aware delegation targets (make ARCH=x86_64 build-coreutils, etc.)
# ═════════════════════════════════════════════════════════════════════════════

ifneq ($(ARCH),)
$(foreach pkg,$(USERLAND_PKGS),$(eval build-$(pkg): build-$(pkg)-$(ARCH)))
$(foreach pkg,$(USERLAND_PKGS),$(eval install-$(pkg): install-$(pkg)-$(ARCH)))
userland: userland-$(ARCH)
install: install-$(ARCH)
else
$(foreach pkg,$(USERLAND_PKGS),$(eval build-$(pkg): $(addprefix build-$(pkg)-,$(TARGETS))))
$(foreach pkg,$(USERLAND_PKGS),$(eval install-$(pkg): $(addprefix install-$(pkg)-,$(TARGETS))))
endif
