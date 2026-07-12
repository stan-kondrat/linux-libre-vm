# ═════════════════════════════════════════════════════════════════════════════
# Cross-compiler toolchain (build from source)
# ═════════════════════════════════════════════════════════════════════════════
#
# Canonical sequence for a bare cross-compiler:
#   1. binutils (assembler, linker, ELF tools)
#   2. Linux kernel headers (installed to sysroot)
#   3. glibc headers + startfiles (minimal — just enough for GCC bootstrap)
#   4. GCC stage 1 (C only, static libgcc)
#   5. glibc full (complete C library linked against stage-1 GCC)
#   6. GCC final (full C/C++ with shared libgcc, libstdc++)
#
# All sources come from sources-patched/ (never from sources/ directly).
# Sources are copied + patched there first; toolchain builds use them as srcdir.
# For packages needing in-tree builds (linux-libre), COPY_PKG creates a copy
# in sources-build/<target>/<pkg>/.
# ═════════════════════════════════════════════════════════════════════════════

# Per-target GCC installdir (contains lib/gcc/<triplet>/, libexec/, etc.)
GCC_INSTALL_x86_64      := $(TOOLCHAIN_PREFIX)/x86_64
GCC_INSTALL_arm64       := $(TOOLCHAIN_PREFIX)/arm64

.PHONY: toolchain toolchain-x86_64 toolchain-arm64
.PHONY: linux-headers linux-headers-x86_64 linux-headers-arm64
.PHONY: build-binutils-x86_64 build-binutils-arm64
.PHONY: build-glibc-headers-x86_64 build-glibc-headers-arm64
.PHONY: build-gcc-stage1-x86_64 build-gcc-stage1-arm64
.PHONY: build-glibc-x86_64 build-glibc-arm64
.PHONY: build-gcc-final-x86_64 build-gcc-final-arm64

# ── Kernel config paths (also used by linux-headers for sysroot) ──────────
# (Defined here so both toolchain and kernel builds can reference them.)
KERNEL_CONFIG_x86_64    := $(CURDIR)/kernel-x86_64.config
KERNEL_CONFIG_arm64     := $(CURDIR)/kernel-arm64.config

# ═════════════════════════════════════════════════════════════════════════════
# 1. Cross binutils — out-of-tree configure from sources-patched/
# ═════════════════════════════════════════════════════════════════════════════

BUILD_BINUTILS_x86_64   := $(BUILD_DIR_x86_64)/binutils
BUILD_BINUTILS_arm64    := $(BUILD_DIR_arm64)/binutils

build-binutils-x86_64: $(SOURCES_PATCHED_DIR)/binutils/.patched
	@echo "=== Building cross binutils (x86_64) ==="
	rm -rf "$(BUILD_BINUTILS_x86_64)"
	mkdir -p "$(BUILD_BINUTILS_x86_64)"
	cd "$(BUILD_BINUTILS_x86_64)" && \
	  "$(SOURCES_PATCHED_DIR)/binutils"/configure \
	    --target=x86_64-linux-gnu \
	    --prefix="$(TOOLCHAIN_PREFIX)/x86_64" \
	    --with-sysroot="$(SYSROOT_x86_64)" \
	    --disable-nls \
	    --disable-werror \
	    --disable-gdb \
	    --disable-gprofng \
	    --disable-libdecnumber \
	    --disable-readline \
	    --disable-sim \
	    CFLAGS="$(COMMON_CFLAGS)"
	$(MAKE) $(PARALLEL) -C "$(BUILD_BINUTILS_x86_64)"
	$(MAKE) -C "$(BUILD_BINUTILS_x86_64)" install
	@echo "=== binutils installed to $(TOOLCHAIN_PREFIX)/x86_64 ==="

build-binutils-arm64: $(SOURCES_PATCHED_DIR)/binutils/.patched
	@echo "=== Building cross binutils (arm64) ==="
	rm -rf "$(BUILD_BINUTILS_arm64)"
	mkdir -p "$(BUILD_BINUTILS_arm64)"
	cd "$(BUILD_BINUTILS_arm64)" && \
	  "$(SOURCES_PATCHED_DIR)/binutils"/configure \
	    --target=aarch64-linux-gnu \
	    --prefix="$(TOOLCHAIN_PREFIX)/arm64" \
	    --with-sysroot="$(SYSROOT_arm64)" \
	    --disable-nls \
	    --disable-werror \
	    --disable-gdb \
	    --disable-gprofng \
	    --disable-libdecnumber \
	    --disable-readline \
	    --disable-sim \
	    CFLAGS="$(COMMON_CFLAGS)"
	$(MAKE) $(PARALLEL) -C "$(BUILD_BINUTILS_arm64)"
	$(MAKE) -C "$(BUILD_BINUTILS_arm64)" install
	@echo "=== binutils installed to $(TOOLCHAIN_PREFIX)/arm64 ==="

# ═════════════════════════════════════════════════════════════════════════════
# 2. Linux kernel headers into sysroot (from sources-patched/ copy)
# ═════════════════════════════════════════════════════════════════════════════
#
# Kernel builds are in-tree; we copy sources-patched/linux-libre to
# sources-build/<target>/linux-libre/ first so sources/ is never touched.

# Per-target copy of linux-libre for linux-headers and kernel builds
$(foreach t,$(TARGETS),$(eval $(call COPY_PKG,linux-libre,$(t))))

linux-headers-x86_64: fake-bin $(BUILD_DIR_x86_64)/linux-libre/.copied
	@echo "=== Configuring and installing x86_64 kernel headers to $(SYSROOT_x86_64) ==="
	cp "$(KERNEL_CONFIG_x86_64)" "$(BUILD_DIR_x86_64)/linux-libre/.config" 2>/dev/null || true
	PATH="$(FAKE_BIN_PATH)" $(MAKE) -C "$(BUILD_DIR_x86_64)/linux-libre" \
	  ARCH=x86_64 olddefconfig 2>/dev/null || true
	PATH="$(FAKE_BIN_PATH)" $(MAKE) -C "$(BUILD_DIR_x86_64)/linux-libre" \
	  ARCH=x86_64 prepare 2>&1 | tail -5 || true
	PATH="$(FAKE_BIN_PATH)" $(MAKE) -C "$(BUILD_DIR_x86_64)/linux-libre" \
	  ARCH=x86_64 \
	  headers_install INSTALL_HDR_PATH="$(SYSROOT_x86_64)/usr"
	@echo "=== x86_64 kernel headers installed ==="

linux-headers-arm64: fake-bin $(BUILD_DIR_arm64)/linux-libre/.copied
	@echo "=== Configuring and installing arm64 kernel headers to $(SYSROOT_arm64) ==="
	cp "$(KERNEL_CONFIG_arm64)" "$(BUILD_DIR_arm64)/linux-libre/.config" 2>/dev/null || true
	PATH="$(FAKE_BIN_PATH)" $(MAKE) -C "$(BUILD_DIR_arm64)/linux-libre" \
	  ARCH=arm64 olddefconfig 2>/dev/null || true
	PATH="$(FAKE_BIN_PATH)" $(MAKE) -C "$(BUILD_DIR_arm64)/linux-libre" \
	  ARCH=arm64 prepare 2>&1 | tail -5 || true
	PATH="$(FAKE_BIN_PATH)" $(MAKE) -C "$(BUILD_DIR_arm64)/linux-libre" \
	  ARCH=arm64 \
	  headers_install INSTALL_HDR_PATH="$(SYSROOT_arm64)/usr"
	@echo "=== arm64 kernel headers installed ==="

linux-headers: linux-headers-x86_64 linux-headers-arm64

# ═════════════════════════════════════════════════════════════════════════════
# 3. glibc headers + startfiles (minimal, for GCC stage 1)
# ═════════════════════════════════════════════════════════════════════════════

BUILD_GLIBC_HEADERS_x86_64 := $(BUILD_DIR_x86_64)/glibc-headers
BUILD_GLIBC_HEADERS_arm64  := $(BUILD_DIR_arm64)/glibc-headers

define GLIBC_HEADERS_RULES
build-glibc-headers-$(1): build-gcc-stage1-$(1)
	@echo "=== Installing glibc headers + startfiles for $(1) ==="
	rm -rf "$$(BUILD_GLIBC_HEADERS_$(1))"
	mkdir -p "$$(BUILD_GLIBC_HEADERS_$(1))"
	cd "$$(BUILD_GLIBC_HEADERS_$(1))" && \
	  PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  CC="$$(TOOLCHAIN_PREFIX)/$(1)/bin/$$(TRIPLET_$(1))-gcc" \
	  "$$(SOURCES_PATCHED_DIR)/glibc"/configure \
	    --host=$$(TRIPLET_$(1)) \
	    --build=$$(HOST_TRIPLET) \
	    --prefix=/usr \
	    --with-headers="$$(SYSROOT_$(1))/usr/include" \
	    --disable-nls \
	    --disable-werror \
	    --disable-timezone-tools \
	    libc_cv_slibdir=/lib64
	# Install headers only
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  $$(MAKE) -C "$$(BUILD_GLIBC_HEADERS_$(1))" install-headers
	# Create stub crt objects (GCC stage1 built with --without-headers
	# so it cannot provide these — we create them from glibc source)
	mkdir -p "$$(SYSROOT_$(1))/usr/lib"
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  CC="$$(TOOLCHAIN_PREFIX)/$(1)/bin/$$(TRIPLET_$(1))-gcc" \
	  $$(MAKE) -C "$$(BUILD_GLIBC_HEADERS_$(1))" \
	    csu/subdir_lib \
	    2>/dev/null || true
	for f in crt1.o crti.o crtn.o; do \
	  found="$$$$(find "$$(BUILD_GLIBC_HEADERS_$(1))" -name "$$$$f" -print -quit)"; \
	  if [ -n "$$$$found" ]; then \
	    cp "$$$$found" "$$(SYSROOT_$(1))/usr/lib/"; \
	  else \
	    printf '/* empty */\n' | \
	      "$$(TOOLCHAIN_PREFIX)/$(1)/bin/$$(TRIPLET_$(1))-gcc" -x c -c -o "$$(SYSROOT_$(1))/usr/lib/$$$$f" - 2>/dev/null || \
	      touch "$$(SYSROOT_$(1))/usr/lib/$$$$f"; \
	  fi; \
	done
	@echo "=== glibc headers + startfiles installed for $(1) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call GLIBC_HEADERS_RULES,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# 4. GCC stage 1 (C only, bootstrap)
# ═════════════════════════════════════════════════════════════════════════════

BUILD_GCC_STAGE1_x86_64 := $(BUILD_DIR_x86_64)/gcc-stage1
BUILD_GCC_STAGE1_arm64  := $(BUILD_DIR_arm64)/gcc-stage1

define GCC_STAGE1_RULES
build-gcc-stage1-$(1): build-binutils-$(1) linux-headers-$(1)
	@echo "=== Building GCC stage 1 for $(1) ==="
	rm -rf "$$(BUILD_GCC_STAGE1_$(1))"
	mkdir -p "$$(BUILD_GCC_STAGE1_$(1))"
	cd "$$(BUILD_GCC_STAGE1_$(1))" && \
	  PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  CC=gcc CXX=g++ \
	  "$$(SOURCES_PATCHED_DIR)/gcc"/configure \
	    --target=$$(TRIPLET_$(1)) \
	    --build=$$(HOST_TRIPLET) \
	    --host=$$(HOST_TRIPLET) \
	    --prefix="$$(GCC_INSTALL_$(1))" \
	    --with-sysroot="$$(SYSROOT_$(1))" \
	    --with-native-system-header-dir=/usr/include \
	    --enable-languages=c \
	    --disable-nls \
	    --disable-libada \
	    --disable-libatomic \
	    --disable-libgomp \
	    --disable-libmudflap \
	    --disable-libquadmath \
	    --disable-libsanitizer \
	    --disable-libssp \
	    --disable-libstdcxx-pch \
	    --disable-libvtv \
	    --disable-multilib \
	    --disable-threads \
	    --without-headers \
	    CFLAGS="$(COMMON_CFLAGS)" \
	    CXXFLAGS="$(COMMON_CFLAGS)" \
	    LDFLAGS="$(COMMON_LDFLAGS)"
	# Build only GCC C frontend and its core libs (skip dependency tracking)
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  CC=gcc CXX=g++ \
	  $$(MAKE) $(PARALLEL) -C "$$(BUILD_GCC_STAGE1_$(1))" all-gcc \
	    CONFIG_SITE= \
	    GCC_CONFIG_ARGUMENTS='$$(GCC_CONFIG_ARGS)'
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  CC=gcc CXX=g++ \
	  $$(MAKE) -C "$$(BUILD_GCC_STAGE1_$(1))" install-gcc \
	    CONFIG_SITE=
	@echo "=== GCC stage 1 installed for $(1) ==="
	@echo "  Compiler: $$(TOOLCHAIN_PREFIX)/$(1)/bin/$$(TRIPLET_$(1))-gcc"
endef

$(foreach t,$(TARGETS),$(eval $(call GCC_STAGE1_RULES,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# 5. glibc full (complete C library)
# ═════════════════════════════════════════════════════════════════════════════

BUILD_GLIBC_x86_64 := $(BUILD_DIR_x86_64)/glibc
BUILD_GLIBC_arm64  := $(BUILD_DIR_arm64)/glibc

define GLIBC_FULL_RULES
build-glibc-$(1): build-glibc-headers-$(1)
	@echo "=== Building full glibc for $(1) ==="
	rm -rf "$$(BUILD_GLIBC_$(1))"
	mkdir -p "$$(BUILD_GLIBC_$(1))"
	cd "$$(BUILD_GLIBC_$(1))" && \
	  PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  CC="$$(TOOLCHAIN_PREFIX)/$(1)/bin/$$(TRIPLET_$(1))-gcc" \
	  CFLAGS="-O2 -pipe" \
	  "$$(SOURCES_PATCHED_DIR)/glibc"/configure \
	    --host=$$(TRIPLET_$(1)) \
	    --build=$$(HOST_TRIPLET) \
	    --prefix=/usr \
	    --with-headers="$$(SYSROOT_$(1))/usr/include" \
	    --disable-nls \
	    --disable-werror \
	    --disable-timezone-tools \
	    libc_cv_slibdir=/lib64
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  $$(MAKE) $(PARALLEL) -C "$$(BUILD_GLIBC_$(1))"
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  $$(MAKE) -C "$$(BUILD_GLIBC_$(1))" \
	  install_root="$$(SYSROOT_$(1))" install
	@echo "=== glibc full installed to $(SYSROOT_$(1)) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call GLIBC_FULL_RULES,$(t))))

# ═════════════════════════════════════════════════════════════════════════════
# 6. GCC final (full C/C++ with shared libgcc, libstdc++)
# ═════════════════════════════════════════════════════════════════════════════

BUILD_GCC_FINAL_x86_64 := $(BUILD_DIR_x86_64)/gcc-final
BUILD_GCC_FINAL_arm64  := $(BUILD_DIR_arm64)/gcc-final

define GCC_FINAL_RULES
build-gcc-final-$(1): build-glibc-$(1)
	@echo "=== Building GCC final for $(1) ==="
	rm -rf "$$(BUILD_GCC_FINAL_$(1))"
	mkdir -p "$$(BUILD_GCC_FINAL_$(1))"
	cd "$$(BUILD_GCC_FINAL_$(1))" && \
	  PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  "$$(SOURCES_PATCHED_DIR)/gcc"/configure \
	    --target=$$(TRIPLET_$(1)) \
	    --build=$$(HOST_TRIPLET) \
	    --host=$$(HOST_TRIPLET) \
	    --prefix="$$(GCC_INSTALL_$(1))" \
	    --with-sysroot="$$(SYSROOT_$(1))" \
	    --with-native-system-header-dir=/usr/include \
	    --enable-languages=c,c++ \
	    --enable-shared \
	    --enable-threads=posix \
	    --disable-nls \
	    --disable-libada \
	    --disable-multilib \
	    CFLAGS="$(COMMON_CFLAGS)" \
	    CXXFLAGS="$(COMMON_CFLAGS)" \
	    LDFLAGS="$(COMMON_LDFLAGS)"
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  $$(MAKE) $(PARALLEL) -C "$$(BUILD_GCC_FINAL_$(1))"
	PATH="$$(TOOLCHAIN_PREFIX)/$(1)/bin:$(FAKE_BIN_PATH)" \
	  $$(MAKE) -C "$$(BUILD_GCC_FINAL_$(1))" install
	@echo "=== GCC final installed for $(1) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call GCC_FINAL_RULES,$(t))))

# ── Aggregate toolchain targets ──────────────────────────────────────────

toolchain-x86_64: build-gcc-final-x86_64
	@echo "=== x86_64 toolchain ready ==="
	@echo "  PATH=$$(TOOLCHAIN_PREFIX)/x86_64/bin:$$$$PATH"

toolchain-arm64: build-gcc-final-arm64
	@echo "=== arm64 toolchain ready ==="
	@echo "  PATH=$$(TOOLCHAIN_PREFIX)/arm64/bin:$$$$PATH"

toolchain: toolchain-x86_64 toolchain-arm64
	@echo "=== All toolchains ready ==="
