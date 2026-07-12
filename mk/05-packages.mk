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

# ═════════════════════════════════════════════════════════════════════════════
# Default aliases — build-<pkg> builds for ALL targets
# ═════════════════════════════════════════════════════════════════════════════

coreutils:   build-coreutils-x86_64 build-coreutils-arm64
bash:        build-bash-x86_64 build-bash-arm64
grep:        build-grep-x86_64 build-grep-arm64
sed:         build-sed-x86_64 build-sed-arm64
gawk:        build-gawk-x86_64 build-gawk-arm64
findutils:   build-findutils-x86_64 build-findutils-arm64
diffutils:   build-diffutils-x86_64 build-diffutils-arm64
gzip:        build-gzip-x86_64 build-gzip-arm64
tar:         build-tar-x86_64 build-tar-arm64
vim:         build-vim-x86_64 build-vim-arm64
iproute2:    build-iproute2-x86_64 build-iproute2-arm64
procps-ng:   build-procps-ng-x86_64 build-procps-ng-arm64
util-linux:  build-util-linux-x86_64 build-util-linux-arm64
runit:       build-runit-x86_64 build-runit-arm64
dhcpcd:      build-dhcpcd-x86_64 build-dhcpcd-arm64

# ═════════════════════════════════════════════════════════════════════════════
# Per-target userland aggregate targets
# ═════════════════════════════════════════════════════════════════════════════

USERLAND_PKGS = coreutils bash grep sed gawk findutils diffutils gzip tar vim \
                iproute2 procps-ng util-linux runit dhcpcd

userland-x86_64: $(addprefix build-,$(addsuffix -x86_64,$(USERLAND_PKGS)))
	@echo "=== All userland packages built (x86_64) ==="

userland-arm64: $(addprefix build-,$(addsuffix -arm64,$(USERLAND_PKGS)))
	@echo "=== All userland packages built (arm64) ==="

userland: userland-x86_64 userland-arm64
	@echo "=== All userland packages built (all targets) ==="

all: check-env build-dirs userland

build: check-env build-dirs userland kernel
	@echo "=== All packages + kernel built for all targets ==="
	@echo "=== All packages built for all targets ==="
	@echo "  Run 'make install' to install all, or 'make ARCH=x86_64 install' / 'make ARCH=arm64 install'"

# ═════════════════════════════════════════════════════════════════════════════
# Per-target install targets
# ═════════════════════════════════════════════════════════════════════════════

install-x86_64: userland-x86_64
	@echo "=== Installing to $(ROOTFS_x86_64) ==="
	mkdir -p "$(ROOTFS_x86_64)"
	for pkg in $(USERLAND_PKGS); do \
	  $(MAKE) install-$$pkg-x86_64; \
	done
	$(MAKE) strip-all-x86_64 2>/dev/null || true
	$(MAKE) prune-docs-x86_64 2>/dev/null || true
	$(MAKE) consolidate-bin-x86_64
	$(MAKE) install-init-x86_64
	@echo "=== Install complete (x86_64) ==="

install-arm64: userland-arm64
	@echo "=== Installing to $(ROOTFS_arm64) ==="
	mkdir -p "$(ROOTFS_arm64)"
	for pkg in $(USERLAND_PKGS); do \
	  $(MAKE) install-$$pkg-arm64; \
	done
	$(MAKE) strip-all-arm64 2>/dev/null || true
	$(MAKE) prune-docs-arm64 2>/dev/null || true
	$(MAKE) consolidate-bin-arm64
	$(MAKE) install-init-arm64
	@echo "=== Install complete (arm64) ==="

install-all: install-x86_64 install-arm64
	@echo "=== All installs complete ==="

install: install-all
	@echo "=== All installs complete ==="

# ═════════════════════════════════════════════════════════════════════════════
# Per-target post-install
# ═════════════════════════════════════════════════════════════════════════════

strip-all-x86_64:
ifneq ($(STRIP),0)
	@echo "=== Stripping x86_64 binaries ==="
	find "$(ROOTFS_x86_64)"/bin "$(ROOTFS_x86_64)"/sbin \
	     "$(ROOTFS_x86_64)"/usr/bin "$(ROOTFS_x86_64)"/usr/sbin \
	     -type f -exec $(CROSS_x86_64)strip -s {} \; 2>/dev/null || true
endif

strip-all-arm64:
ifneq ($(STRIP),0)
	@echo "=== Stripping arm64 binaries ==="
	find "$(ROOTFS_arm64)"/bin "$(ROOTFS_arm64)"/sbin \
	     "$(ROOTFS_arm64)"/usr/bin "$(ROOTFS_arm64)"/usr/sbin \
	     -type f -exec $(CROSS_arm64)strip -s {} \; 2>/dev/null || true
endif

prune-docs-x86_64:
	@echo "=== Pruning docs (x86_64) ==="
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/doc
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/man
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/info
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/locale
	-rm -rf "$(ROOTFS_x86_64)"/tmp/*
	-rm -rf "$(ROOTFS_x86_64)"/var/cache
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/applications
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/icons
	# Strip vim bloat (keep only syntax/, indent/, ftplugin/, autoload/, colors/, plugin/)
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/doc
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/tutor
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/spell
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/print
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/macros
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/tools
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/pack
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/colors/lists
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/colors/tools
	-rm -rf "$(ROOTFS_x86_64)"/usr/share/vim/vim92/import

prune-docs-arm64:
	@echo "=== Pruning docs (arm64) ==="
	-rm -rf "$(ROOTFS_arm64)"/usr/share/doc
	-rm -rf "$(ROOTFS_arm64)"/usr/share/man
	-rm -rf "$(ROOTFS_arm64)"/usr/share/info
	-rm -rf "$(ROOTFS_arm64)"/usr/share/locale
	-rm -rf "$(ROOTFS_arm64)"/tmp/*
	-rm -rf "$(ROOTFS_arm64)"/var/cache
	-rm -rf "$(ROOTFS_arm64)"/usr/share/applications
	-rm -rf "$(ROOTFS_arm64)"/usr/share/icons
	# Strip vim bloat (keep only syntax/, indent/, ftplugin/, autoload/, colors/, plugin/)
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/doc
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/tutor
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/spell
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/print
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/macros
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/tools
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/pack
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/colors/lists
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/colors/tools
	-rm -rf "$(ROOTFS_arm64)"/usr/share/vim/vim92/import

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
	# Move /sbin/* to /bin/*
	if [ -d "$(ROOTFS_$(1))/sbin" ]; then \
	  mv "$(ROOTFS_$(1))/sbin/"* "$(ROOTFS_$(1))/bin/" 2>/dev/null || true; \
	  rmdir "$(ROOTFS_$(1))/sbin" 2>/dev/null || true; \
	fi
	# Create /sbin/init -> /bin/runit-init symlink (kernel looks for /sbin/init)
	mkdir -p "$(ROOTFS_$(1))/sbin"
	ln -sf /bin/runit-init "$(ROOTFS_$(1))/sbin/init"
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
$(foreach pkg,$(USERLAND_PKGS),$(eval build-$(pkg): build-$(pkg)-x86_64 build-$(pkg)-arm64))
$(foreach pkg,$(USERLAND_PKGS),$(eval install-$(pkg): install-$(pkg)-x86_64 install-$(pkg)-arm64))
endif
