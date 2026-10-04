# ═════════════════════════════════════════════════════════════════════════════
# Toolchain from source — stage 0 of self-hosting (see docs/self-hosting.md)
# ═════════════════════════════════════════════════════════════════════════════
#
# Builds a native toolchain (gcc, binutils, glibc, Linux UAPI headers) and the
# tools a kernel build needs (make, m4, bison, flex, bc, perl) from pinned
# sources, and assembles a separate "dev" root filesystem + disk image:
#
#   make toolchain        build everything into $(TC_ROOT) (staging)
#   make install-dev      rootfs/<arch> (normal install) + toolchain → $(TOOLCHAIN_WORK)/rootfs-dev
#   make disk-image-dev   disks/disk-<arch>-dev.img ($(DEV_DISK_SIZE_MB) MB, sparse)
#
# Additive only: the normal build/install/disk-image targets are unchanged.
# Native builds only (the host builds a toolchain for its own architecture).
#
# Sources: binutils, gcc, glibc, bc, perl are git submodules under
# sources/toolchain/ (not fetched by default); make, m4, bison and flex are
# release tarballs (building them from git needs a gnulib bootstrap) pinned by
# SHA-256. Fetch both with: scripts/fetch-toolchain.sh
#
# Work directory: TOOLCHAIN_WORK (default sources-build/<arch>/toolchain). Point
# it at a local disk when the repo is on a shared folder, e.g.
#   make toolchain TOOLCHAIN_WORK=/var/tmp/toolchain
# ═════════════════════════════════════════════════════════════════════════════

.PHONY: toolchain install-dev disk-image-dev toolchain-clean

TC_ARCH         := $(if $(filter aarch64,$(HOST_ARCH)),arm64,$(if $(filter x86_64,$(HOST_ARCH)),x86_64))
TC_SRC          := $(SOURCES_DIR)/toolchain
TC_DIST         := $(TC_SRC)/dist
TOOLCHAIN_WORK  ?= $(BUILD_DIR_$(TC_ARCH))/toolchain
TC_ROOT         := $(TOOLCHAIN_WORK)/root
TC_STAMP        := $(TOOLCHAIN_WORK)/stamps
# Both root filesystems are assembled on the work disk, not in the repo: when
# the repo is a shared folder (UTM VirtFS), setting file modes there fails for
# some files, which then appear as 0600 to the build host (bash without +x)
TC_BASE_ROOTFS  := $(TOOLCHAIN_WORK)/rootfs-base
ROOTFS_DEV      ?= $(TOOLCHAIN_WORK)/rootfs-dev
DEV_DISK_SIZE_MB ?= 8192

# Pinned release tarballs (sources/toolchain/dist, see scripts/fetch-toolchain.sh)
TC_MAKE_TAR     := make-4.4.1.tar.gz
TC_M4_TAR       := m4-1.4.21.tar.xz
TC_BISON_TAR    := bison-3.8.2.tar.xz
TC_FLEX_TAR     := flex-2.6.4.tar.gz

# glibc: libraries in /lib (like the rest of the rootfs); the dynamic linker
# stays where each arch's binaries expect it
TC_RTLDDIR_arm64  := /lib
TC_RTLDDIR_x86_64 := /lib64

TC_CFLAGS       := -O2 -pipe
# Toolchain builds run without LD_LIBRARY_PATH: glibc refuses to configure
# when it contains the current directory (an empty entry, e.g. a stray ':'),
# and host libraries must not leak into the new toolchain anyway
TC_ENV          := env -u LD_LIBRARY_PATH
# Sub-builds must not inherit this make's command line (e.g. ARCH=arm64)
TC_MAKE         := $(TC_ENV) -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES make
TC_JOBS         := -j$$(nproc)

# Source tree from a git submodule, with uniform timestamps (git archive sets
# every file to the commit time, so no generated file looks out of date)
# $(call tc_git_src,<submodule>,<dest dir>)
tc_git_src = rm -rf "$(2)" && mkdir -p "$(2)" && \
	git -C "$(TC_SRC)/$(1)" archive --format=tar HEAD | tar -x -C "$(2)"

# $(call tc_tar_src,<tarball>,<dest parent>)
tc_tar_src = mkdir -p "$(2)" && tar -xf "$(TC_DIST)/$(1)" -C "$(2)"

toolchain: $(TC_STAMP)/linux-headers $(TC_STAMP)/glibc $(TC_STAMP)/binutils \
           $(TC_STAMP)/gcc $(TC_STAMP)/make $(TC_STAMP)/m4 $(TC_STAMP)/bison \
           $(TC_STAMP)/flex $(TC_STAMP)/bc $(TC_STAMP)/perl
	@echo "=== Toolchain ($(TC_ARCH)) staged in $(TC_ROOT) ==="

$(TC_STAMP)/.check:
	@[ -n "$(TC_ARCH)" ] || { echo "toolchain: unsupported host ($(HOST_ARCH)); needs a Linux aarch64 or x86_64 host"; exit 1; }
	@[ -z "$(ARCH)" ] || [ "$(ARCH)" = "$(TC_ARCH)" ] || \
	  { echo "toolchain: native builds only — host is $(TC_ARCH), ARCH=$(ARCH)"; exit 1; }
	@for d in binutils gcc glibc bc perl; do \
	  [ -e "$(TC_SRC)/$$d/.git" ] || { echo "toolchain: sources/toolchain/$$d missing — run scripts/fetch-toolchain.sh"; exit 1; }; \
	done
	@for t in $(TC_MAKE_TAR) $(TC_M4_TAR) $(TC_BISON_TAR) $(TC_FLEX_TAR); do \
	  [ -f "$(TC_DIST)/$$t" ] || { echo "toolchain: $(TC_DIST)/$$t missing — run scripts/fetch-toolchain.sh"; exit 1; }; \
	done
	mkdir -p "$(TC_STAMP)" "$(TC_ROOT)"
	@touch "$@"

# ── Linux UAPI headers (from our linux-libre source, out of tree) ───────────
$(TC_STAMP)/linux-headers: $(TC_STAMP)/.check
	@echo "=== toolchain: Linux UAPI headers ==="
	rm -rf "$(TOOLCHAIN_WORK)/linux-headers"
	$(TC_MAKE) -C "$(LINUX_LIBRE_DIR)" O="$(TOOLCHAIN_WORK)/linux-headers" \
	  ARCH=$(TC_ARCH) INSTALL_HDR_PATH="$(TC_ROOT)/usr" headers_install
	@touch "$@"

# ── glibc ───────────────────────────────────────────────────────────────────
$(TC_STAMP)/glibc: $(TC_STAMP)/linux-headers
	@echo "=== toolchain: glibc ==="
	$(call tc_git_src,glibc,$(TOOLCHAIN_WORK)/glibc-src)
	rm -rf "$(TOOLCHAIN_WORK)/glibc-build" && mkdir -p "$(TOOLCHAIN_WORK)/glibc-build"
	cd "$(TOOLCHAIN_WORK)/glibc-build" && $(TC_ENV) "$(TOOLCHAIN_WORK)/glibc-src/configure" \
	  --prefix=/usr --libdir=/usr/lib --libexecdir=/usr/lib \
	  --with-headers="$(TC_ROOT)/usr/include" --enable-kernel=5.4 --disable-werror \
	  libc_cv_slibdir=/lib libc_cv_rtlddir=$(TC_RTLDDIR_$(TC_ARCH)) \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)"
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/glibc-build" $(TC_JOBS)
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/glibc-build" install \
	  install_root="$(TC_ROOT)" DESTDIR="$(TC_ROOT)"
	@touch "$@"

# ── binutils ────────────────────────────────────────────────────────────────
$(TC_STAMP)/binutils: $(TC_STAMP)/.check
	@echo "=== toolchain: binutils ==="
	$(call tc_git_src,binutils,$(TOOLCHAIN_WORK)/binutils-src)
	rm -rf "$(TOOLCHAIN_WORK)/binutils-build" && mkdir -p "$(TOOLCHAIN_WORK)/binutils-build"
	cd "$(TOOLCHAIN_WORK)/binutils-build" && $(TC_ENV) "$(TOOLCHAIN_WORK)/binutils-src/configure" \
	  --prefix=/usr --libdir=/usr/lib \
	  --disable-gdb --disable-gdbserver --disable-sim --disable-libdecnumber \
	  --disable-readline --disable-gprofng --disable-nls --disable-werror \
	  --enable-deterministic-archives --enable-plugins \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)"
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/binutils-build" $(TC_JOBS) MAKEINFO=true
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/binutils-build" install DESTDIR="$(TC_ROOT)" MAKEINFO=true
	@touch "$@"

# ── gcc (C, C++) ────────────────────────────────────────────────────────────
# gmp/mpfr/mpc/isl: built in-tree from the tarballs gcc's own
# contrib/download_prerequisites fetches and verifies (SHA-512 pinned in gcc)
$(TC_STAMP)/gcc: $(TC_STAMP)/.check
	@echo "=== toolchain: gcc ==="
	$(call tc_git_src,gcc,$(TOOLCHAIN_WORK)/gcc-src)
	cd "$(TOOLCHAIN_WORK)/gcc-src" && { ./contrib/gcc_update --touch >/dev/null 2>&1 || true; } && \
	  ./contrib/download_prerequisites
	rm -rf "$(TOOLCHAIN_WORK)/gcc-build" && mkdir -p "$(TOOLCHAIN_WORK)/gcc-build"
	cd "$(TOOLCHAIN_WORK)/gcc-build" && $(TC_ENV) "$(TOOLCHAIN_WORK)/gcc-src/configure" \
	  --prefix=/usr --libdir=/usr/lib --libexecdir=/usr/lib \
	  --enable-languages=c,c++ --disable-multilib --disable-bootstrap --disable-nls \
	  --disable-libsanitizer --disable-libssp --disable-libquadmath --disable-libvtv \
	  --disable-libgomp --disable-libitm --enable-default-pie --disable-werror \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)" \
	  CFLAGS_FOR_TARGET="$(TC_CFLAGS)" CXXFLAGS_FOR_TARGET="$(TC_CFLAGS)"
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/gcc-build" $(TC_JOBS)
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/gcc-build" install DESTDIR="$(TC_ROOT)"
	ln -sf gcc "$(TC_ROOT)/usr/bin/cc"
	@touch "$@"

# ── make, m4, bison, flex (release tarballs, plain configure) ──────────────
# $(call tc_tarball_rule,<name>,<tarball>,<extra configure args>)
# Source dir = tarball name without .tar.gz/.tar.xz. Inside the template,
# $$(TC_JOBS) stays unexpanded until the recipe runs (it contains $$(nproc)).
define tc_tarball_rule
$(TC_STAMP)/$(1): $(TC_STAMP)/.check
	@echo "=== toolchain: $(1) ==="
	rm -rf "$(TOOLCHAIN_WORK)/$(basename $(basename $(2)))"
	$(call tc_tar_src,$(2),$(TOOLCHAIN_WORK))
	cd "$(TOOLCHAIN_WORK)/$(basename $(basename $(2)))" && \
	  $(TC_ENV) ./configure --prefix=/usr --disable-nls $(3) CFLAGS="$(TC_CFLAGS)"
	$$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/$(basename $(basename $(2)))" $$(TC_JOBS)
	$$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/$(basename $(basename $(2)))" install DESTDIR="$(TC_ROOT)"
	@touch "$$@"
endef
$(eval $(call tc_tarball_rule,make,$(TC_MAKE_TAR),--without-guile))
$(eval $(call tc_tarball_rule,m4,$(TC_M4_TAR),))
$(eval $(call tc_tarball_rule,bison,$(TC_BISON_TAR),))
$(eval $(call tc_tarball_rule,flex,$(TC_FLEX_TAR),))

# ── bc (Gavin Howard's bc; used by the kernel build for timeconst) ──────────
$(TC_STAMP)/bc: $(TC_STAMP)/.check
	@echo "=== toolchain: bc ==="
	$(call tc_git_src,bc,$(TOOLCHAIN_WORK)/bc-src)
	cd "$(TOOLCHAIN_WORK)/bc-src" && $(TC_ENV) CFLAGS="$(TC_CFLAGS)" ./configure.sh --prefix=/usr \
	  --disable-nls --disable-generated-tests --disable-history --disable-man-pages
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/bc-src" $(TC_JOBS)
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/bc-src" install DESTDIR="$(TC_ROOT)"
	@touch "$@"

# ── perl (builds in its source tree) ────────────────────────────────────────
$(TC_STAMP)/perl: $(TC_STAMP)/.check
	@echo "=== toolchain: perl ==="
	$(call tc_git_src,perl,$(TOOLCHAIN_WORK)/perl-src)
	cd "$(TOOLCHAIN_WORK)/perl-src" && $(TC_ENV) sh Configure -des \
	  -Dprefix=/usr -Dvendorprefix=/usr -Doptimize="$(TC_CFLAGS)"
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/perl-src" $(TC_JOBS)
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/perl-src" install DESTDIR="$(TC_ROOT)"
	@# Manual pages are not needed in the image. (-Dman1dir=none made perl
	@# 5.44 write them as *.0 files into the root; remove any such leftovers.)
	rm -rf "$(TC_ROOT)/usr/share/man"
	find "$(TC_ROOT)" -maxdepth 1 -type f -name '*.0' -delete
	@touch "$@"

# ── dev rootfs: normal install + staged toolchain ───────────────────────────
# In the rootfs, /usr/lib64 is a symlink to /lib: anything the toolchain put in
# usr/lib64 is moved to lib in a copy of the staging tree first, and the merge
# uses plain tar (never following symlinks out of the rootfs).
install-dev: toolchain
	@[ -n "$(TC_ARCH)" ] || { echo "install-dev: unsupported host"; exit 1; }
	rm -rf "$(TC_BASE_ROOTFS)"
	$(MAKE) ARCH=$(TC_ARCH) ROOTFS_$(TC_ARCH)="$(TC_BASE_ROOTFS)" install-$(TC_ARCH)
	@echo "=== Assembling dev rootfs: $(ROOTFS_DEV) ==="
	rm -rf "$(ROOTFS_DEV)" "$(TOOLCHAIN_WORK)/merge"
	cp -a "$(TC_BASE_ROOTFS)" "$(ROOTFS_DEV)"
	cp -a "$(TC_ROOT)" "$(TOOLCHAIN_WORK)/merge"
	set -e; M="$(TOOLCHAIN_WORK)/merge"; \
	  if [ -d "$$M/usr/lib64" ] && [ ! -L "$$M/usr/lib64" ]; then \
	    mkdir -p "$$M/lib"; cp -a "$$M/usr/lib64/." "$$M/lib/"; rm -rf "$$M/usr/lib64"; \
	  fi; \
	  find "$$M" -name '*.la' -delete; \
	  (cd "$$M" && tar -cf - .) | (cd "$(ROOTFS_DEV)" && tar -xf -)
	rm -rf "$(TOOLCHAIN_WORK)/merge"
	$(CURDIR)/mk/copy-libs.sh "$(ROOTFS_DEV)" readelf \
	  /usr/lib /usr/lib64 /usr/lib/$(TRIPLET_$(TC_ARCH)) /lib /lib64 /lib/$(TRIPLET_$(TC_ARCH))
	ldconfig -r "$(ROOTFS_DEV)" 2>/dev/null || true
	@# Every program must be executable (a missing +x on /bin/bash makes
	@# runit fail with "access denied" and power the VM off)
	@bad=$$(find "$(ROOTFS_DEV)/bin" "$(ROOTFS_DEV)/sbin" "$(ROOTFS_DEV)/usr/bin" "$(ROOTFS_DEV)/usr/sbin" \
	    -type f ! -perm -u+x 2>/dev/null); \
	  [ -z "$$bad" ] || { echo "ERROR: programs without execute permission:"; echo "$$bad"; exit 1; }
	@echo "=== Dev rootfs ready: $(ROOTFS_DEV) ($$(du -sh "$(ROOTFS_DEV)" | cut -f1)) ==="

disk-image-dev:
	@[ -d "$(ROOTFS_DEV)" ] || { echo "disk-image-dev: run 'make install-dev' first"; exit 1; }
	@echo "=== Creating dev disk image ($(DEV_DISK_SIZE_MB) MB, sparse) ==="
	mkdir -p "$(DISK_DIR)"
	rm -f "$(DISK_DIR)/disk-$(TC_ARCH)-dev.img"
	truncate -s $(DEV_DISK_SIZE_MB)M "$(DISK_DIR)/disk-$(TC_ARCH)-dev.img"
	mke2fs -F -q -t ext4 -b 4096 \
	  -O ^metadata_csum,^orphan_file,^flex_bg,^huge_file,^dir_nlink \
	  -d "$(ROOTFS_DEV)" "$(DISK_DIR)/disk-$(TC_ARCH)-dev.img"
	e2fsck -fn "$(DISK_DIR)/disk-$(TC_ARCH)-dev.img" >/dev/null 2>&1 || true
	tune2fs -f -i 0 -c 0 "$(DISK_DIR)/disk-$(TC_ARCH)-dev.img" >/dev/null 2>&1 || true
	@echo "=== Dev disk image: $(DISK_DIR)/disk-$(TC_ARCH)-dev.img ==="

toolchain-clean:
	rm -rf "$(TOOLCHAIN_WORK)" "$(ROOTFS_DEV)"
