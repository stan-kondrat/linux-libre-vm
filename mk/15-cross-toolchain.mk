# ═════════════════════════════════════════════════════════════════════════════
# Cross toolchains from source (see docs/cross-toolchains.md)
# ═════════════════════════════════════════════════════════════════════════════
#
# Builds a GNU cross toolchain (binutils, gcc C/C++, glibc, Linux UAPI headers)
# for one target from the same pinned sources as the native toolchain
# (mk/14-toolchain.mk, scripts/fetch-toolchain.sh):
#
#   make cross-toolchain TARGET=armv6       build into $(CROSS_WORK)/armv6/<triplet>
#   make cross-toolchain-test TARGET=armv6  compile C and C++ test programs, check ELF
#   make cross-toolchain-dist TARGET=armv6  $(CROSS_DIST)/cross-<triplet>.<host arch>.tar.gz + .sha256
#   make cross-toolchains                   every target in CROSS_TARGETS (build, test)
#   make cross-toolchain-all                every target in CROSS_TARGETS (build, test, dist)
#   make cross-toolchain-clean TARGET=armv6
#
# The dev image contains every target in CROSS_TARGETS under
# /opt/cross/<triplet> (install-dev in mk/14-toolchain.mk), on both hosts.
#
# Runs on a Linux aarch64 or x86_64 host, normally the dev image VM. The
# toolchain is relocatable: the sysroot lives inside the prefix
# (<triplet>/<triplet>/sysroot), so the tarball can be unpacked anywhere.
#
# Sequence: binutils → Linux headers → gcc stage 1 (C only, no libc) → glibc →
# gcc (C, C++). Build directories are removed after each step
# (CROSS_KEEP_BUILD=1 keeps them) so a build fits the dev image's disk.
# glibc needs python3; when the host has none, CPython is built first into
# $(CROSS_WORK)/host-python (build-time only, not part of the toolchain).
# ═════════════════════════════════════════════════════════════════════════════

.PHONY: cross-toolchains cross-toolchain cross-toolchain-test cross-toolchain-dist cross-toolchain-all cross-toolchain-clean

# ── Targets ─────────────────────────────────────────────────────────────────
# XT_TRIPLET_<t>   GNU triplet        XT_KARCH_<t>  kernel ARCH for headers
# XT_GCC_<t>       gcc defaults baked into the compiler for this target
# XT_MACHINE_<t>   expected `readelf -h` Machine of the test programs
# XT_ATTRS_<t>     further `readelf -hA` lines the test programs must contain
#                  (regular expressions, separated by ';')
# XT_RTLDDIR_<t>   directory of the dynamic linker, when not /lib
# XT_CPP_<t>       `gcc -dM -E` lines that must (`+`) or must not (`-`) appear,
#                  separated by ';' — checks the baseline baked into gcc
#
# Naming: the CPU field says what the ISA is (armv6, armv7, i686, riscv64);
# the vendor field marks a variant only when two toolchains would otherwise
# share a triplet (i686-sse2-linux-gnu next to i686-linux-gnu).
# The two 32-bit ARM targets carry the CPU in the triplet, so they can be
# installed side by side (both use the hard-float ABI, /lib/ld-linux-armhf.so.3)
CROSS_TARGETS      ?= arm64 x86_64 armv6 armv7 riscv64 i686 i686-sse2

XT_TRIPLET_arm64   := aarch64-linux-gnu
XT_KARCH_arm64     := arm64
XT_GCC_arm64       :=
XT_MACHINE_arm64   := AArch64
XT_ATTRS_arm64     :=

XT_TRIPLET_x86_64  := x86_64-linux-gnu
XT_KARCH_x86_64    := x86_64
XT_GCC_x86_64      :=
XT_MACHINE_x86_64  := Advanced Micro Devices X86-64
XT_ATTRS_x86_64    :=
XT_RTLDDIR_x86_64  := /lib64

# Raspberry Pi 1 / Zero (BCM2835, ARM1176JZF-S)
XT_TRIPLET_armv6   := armv6-linux-gnueabihf
XT_KARCH_armv6     := arm
XT_GCC_armv6       := --with-arch=armv6 --with-fpu=vfp --with-float=hard --with-mode=arm
XT_MACHINE_armv6   := ARM
XT_ATTRS_armv6     := Tag_CPU_arch: v6$$;Tag_ABI_VFP_args: VFP registers

# ARMv7-A, the Debian armhf baseline (VFPv3-D16, Thumb-2)
XT_TRIPLET_armv7   := armv7-linux-gnueabihf
XT_KARCH_armv7     := arm
XT_GCC_armv7       := --with-arch=armv7-a --with-fpu=vfpv3-d16 --with-float=hard --with-mode=thumb
XT_MACHINE_armv7   := ARM
XT_ATTRS_armv7     := Tag_CPU_arch: v7$$;Tag_ABI_VFP_args: VFP registers

# RV64GC, LP64D ABI (the Linux distribution baseline)
XT_TRIPLET_riscv64 := riscv64-linux-gnu
XT_KARCH_riscv64   := riscv
XT_GCC_riscv64     := --with-arch=rv64gc --with-abi=lp64d
XT_MACHINE_riscv64 := RISC-V
XT_ATTRS_riscv64   := Flags:.*RVC, double-float ABI

# 32-bit x86, any CPU since the Pentium Pro (x87 floating point)
XT_TRIPLET_i686    := i686-linux-gnu
XT_KARCH_i686      := x86
XT_GCC_i686        := --with-arch=i686 --with-tune=generic
XT_MACHINE_i686    := Intel 80386
XT_ATTRS_i686      :=
XT_CPP_i686        := -\#define __SSE2__ 1

# 32-bit x86 with SSE2 (Pentium 4 and later; the baseline of current 32-bit
# distributions), SSE floating point
XT_TRIPLET_i686-sse2 := i686-sse2-linux-gnu
XT_KARCH_i686-sse2   := x86
XT_GCC_i686-sse2     := --with-arch=pentium4 --with-fpmath=sse --with-tune=generic
XT_MACHINE_i686-sse2 := Intel 80386
XT_ATTRS_i686-sse2   :=
XT_CPP_i686-sse2     := +\#define __SSE2__ 1;+\#define __SSE_MATH__ 1

TARGET             ?=
CROSS_WORK         ?= $(TOOLCHAIN_WORK)/cross
CROSS_DIST         ?= $(CROSS_WORK)/dist
CROSS_KEEP_BUILD   ?=

XT_TRIPLET  := $(XT_TRIPLET_$(TARGET))
XT_W        := $(abspath $(CROSS_WORK))/$(TARGET)
XT_PREFIX   := $(XT_W)/$(XT_TRIPLET)
XT_SYSROOT  := $(XT_PREFIX)/$(XT_TRIPLET)/sysroot
XT_STAMP    := $(XT_W)/stamps
XT_ARTIFACT := cross-$(XT_TRIPLET).$(TC_ARCH)
XT_HOSTPY   := $(abspath $(CROSS_WORK))/host-python
# The build machine under a vendor of its own: a target of the host's own
# architecture (aarch64-linux-gnu on arm64) would otherwise canonicalise to the
# build triplet and configure as a native compiler (unprefixed, bootstrapped)
XT_BUILD    := $(HOST_ARCH)-build-linux-gnu
XT_RTLDDIR  := $(or $(XT_RTLDDIR_$(TARGET)),/lib)
# python3 for glibc: the host's, or one built into XT_HOSTPY
XT_NEED_PY  := $(if $(shell command -v python3 2>/dev/null),,1)
XT_PATH     := $(XT_PREFIX)/bin:$(if $(XT_NEED_PY),$(XT_HOSTPY)/bin:)$$PATH
XT_ENV      := $(TC_ENV) PATH="$(XT_PATH)"
XT_MAKE     := $(TC_ENV) -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u MAKEOVERRIDES PATH="$(XT_PATH)" make
xt_rmbuild   = $(if $(CROSS_KEEP_BUILD),true,rm -rf $(1))

cross-toolchain: $(XT_STAMP)/gcc
	@echo "=== Cross toolchain $(XT_TRIPLET) (host $(TC_ARCH)): $(XT_PREFIX) ==="

$(XT_STAMP)/.check:
	@[ -n "$(TC_ARCH)" ] || { echo "cross-toolchain: unsupported host ($(HOST_ARCH)); needs a Linux aarch64 or x86_64 host"; exit 1; }
	@[ -n "$(XT_TRIPLET)" ] || { echo "cross-toolchain: TARGET=<one of: $(CROSS_TARGETS)> required (got '$(TARGET)')"; exit 1; }
	@for d in binutils gcc glibc; do \
	  [ -f "$(TC_SRC)/$$d/configure" ] || { echo "cross-toolchain: sources/toolchain/$$d missing — run scripts/fetch-toolchain.sh"; exit 1; }; \
	done
	@[ -z "$(XT_NEED_PY)" ] || [ -x "$(XT_HOSTPY)/bin/python3" ] || [ -f "$(TC_SRC)/python/configure" ] || \
	  { echo "cross-toolchain: no python3 and sources/toolchain/python missing — run scripts/fetch-toolchain.sh"; exit 1; }
	mkdir -p "$(XT_STAMP)" "$(XT_SYSROOT)/lib" "$(XT_SYSROOT)/usr/lib"
	ln -sfn lib "$(XT_SYSROOT)/lib64"
	ln -sfn lib "$(XT_SYSROOT)/usr/lib64"
	@touch "$@"

# ── python3 for glibc's build scripts (only when the host has none) ─────────
$(XT_HOSTPY)/bin/python3:
	@echo "=== cross-toolchain: host python3 ==="
	$(call tc_git_src,python,$(XT_HOSTPY)-src)
	cd "$(XT_HOSTPY)-src" && $(TC_ENV) ./configure --prefix="$(XT_HOSTPY)" \
	  --without-ensurepip --disable-test-modules
	$(TC_MAKE) -C "$(XT_HOSTPY)-src" $(TC_JOBS)
	$(TC_MAKE) -C "$(XT_HOSTPY)-src" install
	rm -rf "$(XT_HOSTPY)-src"

# ── binutils ────────────────────────────────────────────────────────────────
$(XT_STAMP)/binutils: $(XT_STAMP)/.check
	@echo "=== cross-toolchain $(XT_TRIPLET): binutils ==="
	$(call tc_git_src,binutils,$(XT_W)/binutils-src)
	rm -rf "$(XT_W)/binutils-build" && mkdir -p "$(XT_W)/binutils-build"
	cd "$(XT_W)/binutils-build" && $(XT_ENV) "$(XT_W)/binutils-src/configure" \
	  --build=$(XT_BUILD) --host=$(XT_BUILD) \
	  --target=$(XT_TRIPLET) --prefix="$(XT_PREFIX)" --with-sysroot="$(XT_SYSROOT)" \
	  --disable-gdb --disable-gdbserver --disable-sim --disable-libdecnumber \
	  --disable-readline --disable-gprofng --disable-nls --disable-werror \
	  --disable-multilib --enable-deterministic-archives \
	  --without-debuginfod --without-zstd \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)"
	$(XT_MAKE) -C "$(XT_W)/binutils-build" $(TC_JOBS) MAKEINFO=true
	$(XT_MAKE) -C "$(XT_W)/binutils-build" install MAKEINFO=true
	$(call xt_rmbuild,"$(XT_W)/binutils-src" "$(XT_W)/binutils-build")
	@touch "$@"

# ── Linux UAPI headers into the sysroot ─────────────────────────────────────
$(XT_STAMP)/linux-headers: $(XT_STAMP)/.check
	@echo "=== cross-toolchain $(XT_TRIPLET): Linux UAPI headers ==="
	$(call tc_linux_headers,$(XT_KARCH_$(TARGET)),$(XT_W)/linux-headers,$(XT_SYSROOT)/usr)
	@touch "$@"

# ── gcc source (shared by both gcc stages) ──────────────────────────────────
$(XT_STAMP)/gcc-src: $(XT_STAMP)/.check
	@echo "=== cross-toolchain $(XT_TRIPLET): gcc source ==="
	$(call tc_git_src,gcc,$(XT_W)/gcc-src)
	cd "$(XT_W)/gcc-src" && { ./contrib/gcc_update --touch >/dev/null 2>&1 || true; }
	$(call tc_gcc_prereqs,$(XT_W)/gcc-src)
	@touch "$@"

# ── gcc stage 1: C only, static libgcc, no libc ─────────────────────────────
$(XT_STAMP)/gcc1: $(XT_STAMP)/binutils $(XT_STAMP)/gcc-src
	@echo "=== cross-toolchain $(XT_TRIPLET): gcc stage 1 ==="
	rm -rf "$(XT_W)/gcc1-build" && mkdir -p "$(XT_W)/gcc1-build"
	cd "$(XT_W)/gcc1-build" && $(XT_ENV) "$(XT_W)/gcc-src/configure" \
	  --build=$(XT_BUILD) --host=$(XT_BUILD) \
	  --target=$(XT_TRIPLET) --prefix="$(XT_PREFIX)" --with-sysroot="$(XT_SYSROOT)" \
	  --with-glibc-version=$$(sed -n 's/^#define VERSION "\(.*\)"/\1/p' "$(TC_SRC)/glibc/version.h") \
	  --with-newlib --without-headers --enable-languages=c \
	  --disable-shared --disable-threads --disable-multilib --disable-nls \
	  --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp \
	  --disable-libvtv --disable-libstdcxx --disable-libsanitizer --disable-libitm \
	  --disable-werror --without-zstd $(XT_GCC_$(TARGET)) \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)"
	$(XT_MAKE) -C "$(XT_W)/gcc1-build" $(TC_JOBS) all-gcc all-target-libgcc
	$(XT_MAKE) -C "$(XT_W)/gcc1-build" install-gcc install-target-libgcc
	$(call xt_rmbuild,"$(XT_W)/gcc1-build")
	@touch "$@"

# ── glibc for the target, built by gcc stage 1 ──────────────────────────────
# CXX names the target's g++, which stage 1 lacks: glibc then skips its C++
# programs instead of building them with the host's g++.
# Libraries in /lib and /usr/lib for every target (glibc's defaults differ:
# /usr/lib64 on aarch64, /lib64/lp64d on riscv64, while gcc without multilib
# searches lib); the dynamic linker where gcc points binaries at it
# (XT_RTLDDIR). lib64 -> lib links in the sysroot cover either convention.
$(XT_STAMP)/glibc: $(XT_STAMP)/gcc1 $(XT_STAMP)/linux-headers $(if $(XT_NEED_PY),$(XT_HOSTPY)/bin/python3)
	@echo "=== cross-toolchain $(XT_TRIPLET): glibc ==="
	$(call tc_git_src,glibc,$(XT_W)/glibc-src)
	rm -rf "$(XT_W)/glibc-build" && mkdir -p "$(XT_W)/glibc-build"
	cd "$(XT_W)/glibc-build" && $(XT_ENV) "$(XT_W)/glibc-src/configure" \
	  --host=$(XT_TRIPLET) --build=$(XT_BUILD) \
	  --prefix=/usr --libdir=/usr/lib --with-headers="$(XT_SYSROOT)/usr/include" \
	  libc_cv_slibdir=/lib libc_cv_rtlddir=$(XT_RTLDDIR) \
	  --enable-kernel=5.4 --disable-werror --disable-nscd \
	  CXX="$(XT_TRIPLET)-g++" CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)"
	$(XT_MAKE) -C "$(XT_W)/glibc-build" $(TC_JOBS)
	$(XT_MAKE) -C "$(XT_W)/glibc-build" install \
	  install_root="$(XT_SYSROOT)" DESTDIR="$(XT_SYSROOT)"
	$(call xt_rmbuild,"$(XT_W)/glibc-src" "$(XT_W)/glibc-build")
	@touch "$@"

# ── gcc (C, C++) against the target glibc ───────────────────────────────────
$(XT_STAMP)/gcc: $(XT_STAMP)/glibc
	@echo "=== cross-toolchain $(XT_TRIPLET): gcc ==="
	rm -rf "$(XT_W)/gcc-build" && mkdir -p "$(XT_W)/gcc-build"
	cd "$(XT_W)/gcc-build" && $(XT_ENV) "$(XT_W)/gcc-src/configure" \
	  --build=$(XT_BUILD) --host=$(XT_BUILD) \
	  --target=$(XT_TRIPLET) --prefix="$(XT_PREFIX)" --with-sysroot="$(XT_SYSROOT)" \
	  --enable-languages=c,c++ --enable-shared --enable-threads=posix \
	  --enable-__cxa_atexit --disable-multilib --disable-nls \
	  --disable-libsanitizer --disable-libssp --disable-libquadmath --disable-libvtv \
	  --disable-libgomp --disable-libitm --enable-default-pie --disable-werror \
	  --without-zstd $(XT_GCC_$(TARGET)) \
	  CFLAGS="$(TC_CFLAGS)" CXXFLAGS="$(TC_CFLAGS)" \
	  CFLAGS_FOR_TARGET="$(TC_CFLAGS)" CXXFLAGS_FOR_TARGET="$(TC_CFLAGS)"
	$(XT_MAKE) -C "$(XT_W)/gcc-build" $(TC_JOBS)
	$(XT_MAKE) -C "$(XT_W)/gcc-build" install
	find "$(XT_PREFIX)" -name '*.la' -delete
	rm -rf "$(XT_PREFIX)/share/info" "$(XT_PREFIX)/share/man"
	$(call xt_rmbuild,"$(XT_W)/gcc-build" "$(XT_W)/gcc-src")
	@# What the toolchain is, for consumers that pin it (eclogite)
	{ echo "triplet=$(XT_TRIPLET)"; echo "target=$(TARGET)"; echo "host=$(TC_ARCH)"; \
	  echo "gcc_options=$(XT_GCC_$(TARGET))"; \
	  for d in binutils gcc glibc; do \
	    echo "$$d=$$(sed -n "/sources\/toolchain\/$$d\"/,/^\[/s/^[[:space:]]*ref = \(refs\/tags\/\)\{0,1\}//p" "$(CURDIR)/.gitmodules")"; \
	  done; \
	  echo "linux_headers=$$($(TC_MAKE) -s -C "$(LINUX_LIBRE_DIR)" kernelversion)"; \
	} > "$(XT_PREFIX)/BUILD-INFO"
	@touch "$@"

# ── Test: C and C++ programs link against the sysroot; ELF matches target ───
cross-toolchain-test: $(XT_STAMP)/gcc
	@echo "=== cross-toolchain $(XT_TRIPLET): test ==="
	rm -rf "$(XT_W)/test" && mkdir -p "$(XT_W)/test"
	printf '#include <stdio.h>\n#include <math.h>\nint main(void){printf("hello %%g\\n", sqrt(2.0));return 0;}\n' > "$(XT_W)/test/hello.c"
	printf '#include <iostream>\n#include <thread>\nint main(){std::thread t([]{std::cout<<"hello c++"<<std::endl;});t.join();}\n' > "$(XT_W)/test/hello.cpp"
	cd "$(XT_W)/test" && $(XT_ENV) $(XT_TRIPLET)-gcc -O2 -o hello hello.c -lm
	cd "$(XT_W)/test" && $(XT_ENV) $(XT_TRIPLET)-gcc -O2 -static -o hello-static hello.c -lm
	cd "$(XT_W)/test" && $(XT_ENV) $(XT_TRIPLET)-g++ -O2 -o hello-cxx hello.cpp
	@set -e; cd "$(XT_W)/test"; for f in hello hello-static hello-cxx; do \
	  m=$$($(XT_ENV) $(XT_TRIPLET)-readelf -h $$f | sed -n 's/^ *Machine: *//p'); \
	  [ "$$m" = "$(XT_MACHINE_$(TARGET))" ] || { echo "FAIL: $$f Machine '$$m', want '$(XT_MACHINE_$(TARGET))'"; exit 1; }; \
	  i=$$($(XT_ENV) $(XT_TRIPLET)-readelf -l $$f | sed -n 's/.*interpreter: \(.*\)]/\1/p'); \
	  echo "  $$f: $$m$${i:+, interpreter $$i}"; \
	  if [ -n "$$i" ]; then [ -e "$(XT_SYSROOT)$$i" ] || { echo "FAIL: $$i not in sysroot"; exit 1; }; fi; \
	done
	@set -e; a=$$($(XT_ENV) $(XT_TRIPLET)-readelf -hA "$(XT_W)/test/hello"); \
	  attrs='$(XT_ATTRS_$(TARGET))'; IFS=';'; for p in $$attrs; do \
	    echo "$$a" | grep -q -- "$$p" || { echo "FAIL: hello has no line matching '$$p'"; echo "$$a"; exit 1; }; \
	    echo "  hello: $$(echo "$$a" | grep -m1 -- "$$p" | sed 's/^ *//')"; \
	  done
	@set -e; d=$$($(XT_ENV) $(XT_TRIPLET)-gcc -dM -E - </dev/null); \
	  checks='$(XT_CPP_$(TARGET))'; IFS=';'; for c in $$checks; do \
	    l=$${c#?}; \
	    case $$c in \
	      +*) echo "$$d" | grep -qxF -- "$$l" || { echo "FAIL: gcc does not predefine '$$l'"; exit 1; } ;; \
	      -*) ! echo "$$d" | grep -qxF -- "$$l" || { echo "FAIL: gcc predefines '$$l'"; exit 1; } ;; \
	    esac; \
	    echo "  gcc: $$c"; \
	  done
	@echo "=== cross-toolchain $(XT_TRIPLET): test passed ==="

# ── Release artifact ────────────────────────────────────────────────────────
cross-toolchain-dist: $(XT_STAMP)/gcc
	mkdir -p "$(CROSS_DIST)"
	tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 \
	  -C "$(XT_W)" -cf - "$(XT_TRIPLET)" | gzip -n -9 > "$(CROSS_DIST)/$(XT_ARTIFACT).tar.gz.part"
	mv "$(CROSS_DIST)/$(XT_ARTIFACT).tar.gz.part" "$(CROSS_DIST)/$(XT_ARTIFACT).tar.gz"
	cd "$(CROSS_DIST)" && sha256sum "$(XT_ARTIFACT).tar.gz" > "$(XT_ARTIFACT).tar.gz.sha256"
	@echo "=== $(CROSS_DIST)/$(XT_ARTIFACT).tar.gz ($$(du -h "$(CROSS_DIST)/$(XT_ARTIFACT).tar.gz" | cut -f1)) ==="

# Build and test every target (install-dev puts them into the dev image)
cross-toolchains:
	@set -e; for t in $(CROSS_TARGETS); do \
	  $(MAKE) --no-print-directory TARGET=$$t cross-toolchain cross-toolchain-test; \
	done

cross-toolchain-all:
	@set -e; for t in $(CROSS_TARGETS); do \
	  $(MAKE) --no-print-directory TARGET=$$t cross-toolchain cross-toolchain-test cross-toolchain-dist; \
	done

cross-toolchain-clean:
	@[ -n "$(XT_TRIPLET)" ] || { echo "cross-toolchain-clean: TARGET=<one of: $(CROSS_TARGETS)> required"; exit 1; }
	rm -rf "$(XT_W)"
