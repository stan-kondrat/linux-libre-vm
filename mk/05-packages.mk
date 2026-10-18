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

# ── Aliases: <pkg> builds it for all targets ───────────────────────────────

.PHONY: $(USERLAND_PKGS)
$(foreach p,$(USERLAND_PKGS),$(eval $(p): $(addprefix build-$(p)-,$(TARGETS))))

# ── Aggregates ─────────────────────────────────────────────────────────────

$(foreach a,$(TARGETS),$(eval userland-$(a): $(addprefix build-,$(addsuffix -$(a),$(USERLAND_PKGS)))))

userland: $(addprefix userland-,$(BUILD_ARCHS))

all: check-env build-dirs userland

build: check-env build-dirs userland kernel
	@echo "=== Userland + kernel built: $(BUILD_ARCHS) ==="
	@echo "  Next: make install disk-image"

install-all: $(addprefix install-,$(BUILD_ARCHS))

install: install-all

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
	$$(MAKE) strip-all-$(1)
	$$(MAKE) prune-$(1)
	$$(MAKE) consolidate-bin-$(1)
	$$(MAKE) install-init-$(1)
	@echo "=== Install complete ($(1)): $$$$(du -sh "$(ROOTFS_$(1))" | cut -f1) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_ARCH,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# Shared libraries: the dynamic linker plus everything the binaries need
# ═════════════════════════════════════════════════════════════════════════════
# Taken from the cross sysroot, or from the host for native builds.
# copy-libs.sh follows DT_NEEDED recursively; libraries already in the rootfs
# (libcrypto from install-openssl) are kept. The NSS modules are loaded with
# dlopen, so they are named explicitly (stubs since glibc 2.34; copied when
# present).

LIB_DIRS = $(foreach d,usr/lib usr/lib64 usr/lib/$(MULTIARCH_$(1)) lib lib64 lib/$(MULTIARCH_$(1)),$(SYSROOT_$(1))/$(d))

define INSTALL_LIBS
install-libs-$(1):
	@echo "=== Installing shared libraries ($(1)) ==="
	mkdir -p "$(ROOTFS_$(1))/lib" "$(ROOTFS_$(1))$(dir $(LDSO_$(1)))"
	set -e; for d in $(call LIB_DIRS,$(1)); do \
	  [ -e "$$$$d/$(notdir $(LDSO_$(1)))" ] && { cp -L "$$$$d/$(notdir $(LDSO_$(1)))" "$(ROOTFS_$(1))$(LDSO_$(1))"; break; }; \
	done; \
	[ -e "$(ROOTFS_$(1))$(LDSO_$(1))" ] || { echo "ERROR: $(notdir $(LDSO_$(1))) not found in $(call LIB_DIRS,$(1))"; exit 1; }
	# A dynamic linker in /lib is also reachable as /lib64/<name>
	$(if $(filter /lib/,$(dir $(LDSO_$(1)))),mkdir -p "$(ROOTFS_$(1))/lib64" && ln -sf $(LDSO_$(1)) "$(ROOTFS_$(1))/lib64/")
	for lib in libnss_files.so.2 libnss_dns.so.2; do \
	  for d in $(call LIB_DIRS,$(1)); do \
	    [ -e "$$$$d/$$$$lib" ] && { cp -L "$$$$d/$$$$lib" "$(ROOTFS_$(1))/lib/"; break; }; \
	  done; \
	done
	$(CURDIR)/mk/copy-libs.sh "$(ROOTFS_$(1))" $(CROSS_$(1))readelf $(call LIB_DIRS,$(1))
	# The dynamic linker may search /usr/lib64: point it at /lib
	ln -sfn /lib "$(ROOTFS_$(1))/usr/lib64"
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_LIBS,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# Strip and prune
# ═════════════════════════════════════════════════════════════════════════════

# Every ELF file (programs and libraries), with the target's strip; other
# files (scripts) are skipped, and a strip failure fails the install. Some
# packages install read-only programs (dhcpcd: 555), which strip cannot
# rewrite: they are made writable for it and get their mode back.
define STRIP_ALL
strip-all-$(1):
ifneq ($(STRIP),0)
	@echo "=== Stripping $(1) binaries ==="
	find "$(ROOTFS_$(1))" -type f \( -perm -u+x -o -name '*.so*' \) | while read -r f; do \
	  [ "$$$$(head -c 4 "$$$$f" | od -An -c | tr -d ' ')" = '177ELF' ] || continue; \
	  m=$$$$(stat -c %a "$$$$f"); chmod u+w "$$$$f"; \
	  $(CROSS_$(1))strip --strip-unneeded "$$$$f" || exit 1; \
	  chmod "$$$$m" "$$$$f"; \
	done
endif
endef

$(foreach t,$(TARGETS),$(eval $(call STRIP_ALL,$(t))))

# What the image does not need: documentation, locales, headers, static
# libraries and libtool files, bash loadable builtins and completions, and
# the vim runtime (vim is built with --with-features=tiny: no syntax, no
# filetype plugins, no Vim script — only defaults.vim is read)
PRUNE_PATHS := usr/share/doc usr/share/man usr/share/info usr/share/locale \
               usr/share/applications usr/share/icons usr/share/bash-completion \
               usr/share/aclocal usr/share/pkgconfig usr/include \
               usr/lib/pkgconfig usr/lib/bash var/cache

define PRUNE
prune-$(1):
	@echo "=== Pruning ($(1)) ==="
	cd "$(ROOTFS_$(1))" && rm -rf $(PRUNE_PATHS) tmp/*
	find "$(ROOTFS_$(1))" -type f \( -name '*.a' -o -name '*.la' \) -delete
	for d in "$(ROOTFS_$(1))"/usr/share/vim/vim*; do \
	  [ -d "$$$$d" ] || continue; \
	  find "$$$$d" -mindepth 1 -maxdepth 1 ! -name defaults.vim -exec rm -rf {} +; \
	done
endef

$(foreach t,$(TARGETS),$(eval $(call PRUNE,$(t))))

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
