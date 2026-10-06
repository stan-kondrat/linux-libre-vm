# ═════════════════════════════════════════════════════════════════════════════
# Toolchain from source — stage 0 of self-hosting (see docs/self-hosting.md)
# ═════════════════════════════════════════════════════════════════════════════
#
# Builds a native toolchain (gcc, binutils, glibc, Linux UAPI headers) and the
# tools a kernel build needs (make, m4, bison, flex, bc, perl), plus Python 3
# and Node.js, from pinned sources, and assembles a separate "dev" root
# filesystem + disk image:
#
#   make toolchain        build everything into $(TC_ROOT) (staging)
#   make install-dev      rootfs/<arch> (normal install) + toolchain + cross
#                         toolchains (mk/15-cross-toolchain.mk) → $(TOOLCHAIN_WORK)/rootfs-dev
#   make disk-image-dev   disks/disk-<arch>-dev.img ($(DEV_DISK_SIZE_MB) MB, sparse)
#
# Additive only: the normal build/install/disk-image targets are unchanged.
# Native builds only (the host builds a toolchain for its own architecture).
#
# Sources: binutils, gcc, glibc, bc, perl, python, node are git submodules under
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
TC_ZLIB_TAR     := zlib-1.3.2.tar.gz
TC_BZIP2_TAR    := bzip2-1.0.8.tar.gz
# zlib and bzip2 are also installed here, alone, so Python can link them
# statically without seeing the staged glibc in TC_ROOT
TC_DEPS         := $(TOOLCHAIN_WORK)/deps

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
# Node (V8): some compile jobs need ~2.4 GB — jobs limited to one per 2.5 GB
TC_NODE_JOBS    := -j$$(n=$$(nproc); m=$$(awk '/^MemTotal:/ { print int($$2 / 2621440) }' /proc/meminfo); \
                     [ "$$m" -ge 1 ] || m=1; [ "$$m" -lt "$$n" ] && echo "$$m" || echo "$$n")

# Source tree from a git submodule, with uniform timestamps (git archive sets
# every file to the commit time, so no generated file looks out of date).
# Without git (the dev image has none) the checkout is copied instead and
# every file gets the same timestamp.
# $(call tc_git_src,<submodule>,<dest dir>)
tc_git_src = rm -rf "$(2)" && mkdir -p "$(2)" && \
	if command -v git >/dev/null 2>&1 && git -C "$(TC_SRC)/$(1)" rev-parse -q --verify HEAD >/dev/null 2>&1; then \
	  git -C "$(TC_SRC)/$(1)" archive --format=tar HEAD | tar -x -C "$(2)"; \
	else \
	  (cd "$(TC_SRC)/$(1)" && tar --exclude=./.git -cf - .) | tar -x -C "$(2)" && \
	  touch "$(2).ts" && find "$(2)" -exec touch -h -r "$(2).ts" {} + && rm -f "$(2).ts"; \
	fi

# Release tarball into <dest parent>; uses the copy scripts/fetch-toolchain.sh
# unpacked next to it when present (the dev image has no bzip2/xz)
# $(call tc_tar_src,<tarball>,<dest parent>)
tc_tar_src = mkdir -p "$(2)" && \
	if [ -d "$(TC_DIST)/$(basename $(basename $(1)))" ]; then \
	  (cd "$(TC_DIST)" && tar -cf - "$(basename $(basename $(1)))") | tar -x -C "$(2)"; \
	else tar -xf "$(TC_DIST)/$(1)" -C "$(2)"; fi

# gcc's in-tree gmp/mpfr/mpc/isl: the versions its contrib/download_prerequisites
# names, fetched and SHA-512 verified by scripts/fetch-toolchain.sh (no network
# during the build). $(call tc_gcc_prereqs,<gcc source dir>)
tc_gcc_prereqs = set -e; for v in gmp mpfr mpc isl; do \
	  t=$$(sed -n "s/^$$v='\(.*\)'$$/\1/p" "$(1)/contrib/download_prerequisites"); \
	  d=$${t%.tar.*}; \
	  [ -f "$(TC_DIST)/$$t" ] || { echo "toolchain: $(TC_DIST)/$$t missing — run scripts/fetch-toolchain.sh"; exit 1; }; \
	  rm -rf "$(1)/$$d" "$(1)/$$v"; \
	  if [ -d "$(TC_DIST)/$$d" ]; then (cd "$(TC_DIST)" && tar -cf - "$$d") | tar -x -C "$(1)"; \
	  else tar -xf "$(TC_DIST)/$$t" -C "$(1)"; fi; \
	  ln -s "$$d" "$(1)/$$v"; \
	done

# Linux UAPI headers: `make headers` plus a tar copy of the *.h files — the
# same result as headers_install, which needs rsync (not in the dev image)
# $(call tc_linux_headers,<kernel ARCH>,<build dir>,<dest usr dir>)
tc_linux_headers = rm -rf "$(2)" && \
	$(TC_MAKE) -C "$(LINUX_LIBRE_DIR)" O="$(2)" ARCH=$(1) headers && \
	mkdir -p "$(3)" && (cd "$(2)/usr" && find include -name '*.h' | tar -cf - -T -) | tar -x -C "$(3)" && \
	rm -rf "$(2)"

toolchain: $(TC_STAMP)/linux-headers $(TC_STAMP)/glibc $(TC_STAMP)/binutils \
           $(TC_STAMP)/gcc $(TC_STAMP)/make $(TC_STAMP)/m4 $(TC_STAMP)/bison \
           $(TC_STAMP)/flex $(TC_STAMP)/bc $(TC_STAMP)/perl \
           $(TC_STAMP)/zlib $(TC_STAMP)/bzip2 $(TC_STAMP)/python $(TC_STAMP)/node
	@echo "=== Toolchain ($(TC_ARCH)) staged in $(TC_ROOT) ==="

$(TC_STAMP)/.check:
	@[ -n "$(TC_ARCH)" ] || { echo "toolchain: unsupported host ($(HOST_ARCH)); needs a Linux aarch64 or x86_64 host"; exit 1; }
	@[ -z "$(ARCH)" ] || [ "$(ARCH)" = "$(TC_ARCH)" ] || \
	  { echo "toolchain: native builds only — host is $(TC_ARCH), ARCH=$(ARCH)"; exit 1; }
	@for d in binutils gcc glibc bc perl python node; do \
	  [ -e "$(TC_SRC)/$$d/.git" ] || { echo "toolchain: sources/toolchain/$$d missing — run scripts/fetch-toolchain.sh"; exit 1; }; \
	done
	@for t in $(TC_MAKE_TAR) $(TC_M4_TAR) $(TC_BISON_TAR) $(TC_FLEX_TAR) $(TC_ZLIB_TAR) $(TC_BZIP2_TAR); do \
	  [ -f "$(TC_DIST)/$$t" ] || { echo "toolchain: $(TC_DIST)/$$t missing — run scripts/fetch-toolchain.sh"; exit 1; }; \
	done
	mkdir -p "$(TC_STAMP)" "$(TC_ROOT)"
	@touch "$@"

# ── Linux UAPI headers (from our linux-libre source, out of tree) ───────────
$(TC_STAMP)/linux-headers: $(TC_STAMP)/.check
	@echo "=== toolchain: Linux UAPI headers ==="
	$(call tc_linux_headers,$(TC_ARCH),$(TOOLCHAIN_WORK)/linux-headers,$(TC_ROOT)/usr)
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
# Optional libraries configure would pick up from the build host (debuginfod,
# zstd) are disabled: the toolchain must not depend on what the host has
# installed (a dev image built on Void got a readelf needing libdebuginfod)
$(TC_STAMP)/binutils: $(TC_STAMP)/.check
	@echo "=== toolchain: binutils ==="
	$(call tc_git_src,binutils,$(TOOLCHAIN_WORK)/binutils-src)
	rm -rf "$(TOOLCHAIN_WORK)/binutils-build" && mkdir -p "$(TOOLCHAIN_WORK)/binutils-build"
	cd "$(TOOLCHAIN_WORK)/binutils-build" && $(TC_ENV) "$(TOOLCHAIN_WORK)/binutils-src/configure" \
	  --prefix=/usr --libdir=/usr/lib \
	  --disable-gdb --disable-gdbserver --disable-sim --disable-libdecnumber \
	  --disable-readline --disable-gprofng --disable-nls --disable-werror \
	  --enable-deterministic-archives --enable-plugins \
	  --without-debuginfod --without-zstd \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)"
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/binutils-build" $(TC_JOBS) MAKEINFO=true
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/binutils-build" install DESTDIR="$(TC_ROOT)" MAKEINFO=true
	@touch "$@"

# ── gcc (C, C++) ────────────────────────────────────────────────────────────
# gmp/mpfr/mpc/isl: built in-tree (see tc_gcc_prereqs)
$(TC_STAMP)/gcc: $(TC_STAMP)/.check
	@echo "=== toolchain: gcc ==="
	$(call tc_git_src,gcc,$(TOOLCHAIN_WORK)/gcc-src)
	cd "$(TOOLCHAIN_WORK)/gcc-src" && { ./contrib/gcc_update --touch >/dev/null 2>&1 || true; }
	$(call tc_gcc_prereqs,$(TOOLCHAIN_WORK)/gcc-src)
	rm -rf "$(TOOLCHAIN_WORK)/gcc-build" && mkdir -p "$(TOOLCHAIN_WORK)/gcc-build"
	cd "$(TOOLCHAIN_WORK)/gcc-build" && $(TC_ENV) "$(TOOLCHAIN_WORK)/gcc-src/configure" \
	  --prefix=/usr --libdir=/usr/lib --libexecdir=/usr/lib \
	  --enable-languages=c,c++ --disable-multilib --disable-bootstrap --disable-nls \
	  --disable-libsanitizer --disable-libssp --disable-libquadmath --disable-libvtv \
	  --disable-libgomp --disable-libitm --enable-default-pie --disable-werror \
	  --without-zstd \
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

# ── zlib, bzip2 (libraries for Python's zlib and bz2 modules) ──────────────
# Built with -fPIC so the static libraries can go into Python's shared
# extension modules
$(TC_STAMP)/zlib: $(TC_STAMP)/.check
	@echo "=== toolchain: zlib ==="
	rm -rf "$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_ZLIB_TAR)))"
	$(call tc_tar_src,$(TC_ZLIB_TAR),$(TOOLCHAIN_WORK))
	cd "$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_ZLIB_TAR)))" && \
	  $(TC_ENV) CFLAGS="$(TC_CFLAGS) -fPIC" ./configure --prefix=/usr --libdir=/usr/lib
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_ZLIB_TAR)))" $(TC_JOBS)
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_ZLIB_TAR)))" install DESTDIR="$(TC_DEPS)"
	rm -rf "$(TC_DEPS)/usr/share/man"
	(cd "$(TC_DEPS)" && tar -cf - .) | (cd "$(TC_ROOT)" && tar -xf -)
	@touch "$@"

# bzip2 has a plain Makefile; its install target writes absolute symlinks,
# so the few files needed are installed directly
$(TC_STAMP)/bzip2: $(TC_STAMP)/.check
	@echo "=== toolchain: bzip2 ==="
	rm -rf "$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_BZIP2_TAR)))"
	$(call tc_tar_src,$(TC_BZIP2_TAR),$(TOOLCHAIN_WORK))
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_BZIP2_TAR)))" $(TC_JOBS) \
	  CFLAGS="$(TC_CFLAGS) -fPIC -D_FILE_OFFSET_BITS=64" libbz2.a bzip2
	set -e; S="$(TOOLCHAIN_WORK)/$(basename $(basename $(TC_BZIP2_TAR)))"; \
	  for R in "$(TC_DEPS)" "$(TC_ROOT)"; do \
	    install -D -m 755 "$$S/bzip2" "$$R/usr/bin/bzip2"; \
	    ln -sf bzip2 "$$R/usr/bin/bunzip2"; ln -sf bzip2 "$$R/usr/bin/bzcat"; \
	    install -D -m 644 "$$S/bzlib.h" "$$R/usr/include/bzlib.h"; \
	    install -D -m 644 "$$S/libbz2.a" "$$R/usr/lib/libbz2.a"; \
	  done
	@touch "$@"

# ── Python 3 (CPython) ──────────────────────────────────────────────────────
# zlib and bz2 are linked statically from TC_DEPS. Modules whose libraries are
# not in the dev image (OpenSSL, libffi, SQLite, xz, zstd, readline, ncurses)
# are left out by configure
$(TC_STAMP)/python: $(TC_STAMP)/zlib $(TC_STAMP)/bzip2
	@echo "=== toolchain: python ==="
	$(call tc_git_src,python,$(TOOLCHAIN_WORK)/python-src)
	rm -rf "$(TOOLCHAIN_WORK)/python-build" && mkdir -p "$(TOOLCHAIN_WORK)/python-build"
	cd "$(TOOLCHAIN_WORK)/python-build" && $(TC_ENV) "$(TOOLCHAIN_WORK)/python-src/configure" \
	  --prefix=/usr --libdir=/usr/lib --without-ensurepip --disable-test-modules \
	  ZLIB_CFLAGS="-I$(TC_DEPS)/usr/include" ZLIB_LIBS="$(TC_DEPS)/usr/lib/libz.a" \
	  BZIP2_CFLAGS="-I$(TC_DEPS)/usr/include" BZIP2_LIBS="$(TC_DEPS)/usr/lib/libbz2.a" \
	  CFLAGS="$(TC_CFLAGS)"
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/python-build" $(TC_JOBS)
	$(TC_MAKE) -C "$(TOOLCHAIN_WORK)/python-build" install DESTDIR="$(TC_ROOT)"
	rm -rf "$(TC_ROOT)/usr/share/man"
	@# python3 for the node build, whether or not the host has one (CPython
	@# finds its library relative to the real path of its executable)
	mkdir -p "$(TOOLCHAIN_WORK)/pybin"
	ln -sf "$(TC_ROOT)/usr/bin/python3" "$(TOOLCHAIN_WORK)/pybin/python3"
	ln -sf "$(TC_ROOT)/usr/bin/python3" "$(TOOLCHAIN_WORK)/pybin/python3.14"
	"$(TOOLCHAIN_WORK)/pybin/python3" -c 'import sys, zlib, bz2; print("  python", sys.version.split()[0], sys.prefix, "zlib", zlib.ZLIB_RUNTIME_VERSION)'
	@touch "$@"

# ── Node.js (builds in its source tree; V8, ICU, OpenSSL etc. are bundled) ─
$(TC_STAMP)/node: $(TC_STAMP)/python
	@echo "=== toolchain: node ==="
	$(call tc_git_src,node,$(TOOLCHAIN_WORK)/node-src)
	cd "$(TOOLCHAIN_WORK)/node-src" && $(TC_ENV) PATH="$(TOOLCHAIN_WORK)/pybin:$$PATH" \
	  ./configure --prefix=/usr
	$(TC_ENV) -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES PATH="$(TOOLCHAIN_WORK)/pybin:$$PATH" \
	  make -C "$(TOOLCHAIN_WORK)/node-src" $(TC_NODE_JOBS)
	$(TC_ENV) -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES PATH="$(TOOLCHAIN_WORK)/pybin:$$PATH" \
	  make -C "$(TOOLCHAIN_WORK)/node-src" install DESTDIR="$(TC_ROOT)" PREFIX=/usr
	strip "$(TC_ROOT)/usr/bin/node"
	rm -rf "$(TC_ROOT)/usr/share/man" "$(TC_ROOT)/usr/share/doc/node"
	@touch "$@"

# ── dev rootfs: normal install + staged toolchain ───────────────────────────
# In the rootfs, /usr/lib64 is a symlink to /lib: anything the toolchain put in
# usr/lib64 is moved to lib in a copy of the staging tree first, and the merge
# uses plain tar (never following symlinks out of the rootfs). Every cross
# toolchain in CROSS_TARGETS goes to /opt/cross/<triplet> (relocatable; on
# PATH through /etc/profile) before copy-libs, so their host libraries are
# copied too.
install-dev: toolchain cross-toolchains
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
	@# #!/usr/bin/env scripts (npm, many Python and shell tools)
	[ -e "$(ROOTFS_DEV)/usr/bin/env" ] || ln -s ../../bin/env "$(ROOTFS_DEV)/usr/bin/env"
	mkdir -p "$(ROOTFS_DEV)/opt/cross"
	set -e; $(foreach t,$(CROSS_TARGETS),\
	  (cd "$(CROSS_WORK)/$(t)" && tar -cf - "$(XT_TRIPLET_$(t))") | (cd "$(ROOTFS_DEV)/opt/cross" && tar -xf -);)
	printf '%s\n' '# Dev image: cross toolchains (/opt/cross/<triplet>/bin) on PATH' \
	  'for d in /opt/cross/*/bin; do [ -d "$$d" ] && PATH=$$PATH:$$d; done; unset d; export PATH' \
	  > "$(ROOTFS_DEV)/etc/profile"
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
