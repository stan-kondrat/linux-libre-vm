# ═════════════════════════════════════════════════════════════════════════════
# Variables, directories, and common flags
# ═════════════════════════════════════════════════════════════════════════════

.DEFAULT_GOAL := help

# ── Host detection ──────────────────────────────────────────────────────────
HOST_ARCH       := $(shell gcc -dumpmachine | sed 's/-.*//')
HOST_TRIPLET    := $(shell gcc -dumpmachine)

# ── Target architectures ────────────────────────────────────────────────────
TARGETS         := x86_64 arm64
# Architectures built by aggregate targets (build, kernel, install, disk-image,
# check-env): only $(ARCH) when set, e.g. `make ARCH=arm64 build`
BUILD_ARCHS     := $(or $(ARCH),$(TARGETS))

# ── Per-target triplet and cross prefix ────────────────────────────────────
# Toolchain is provided by the host system, not built from source.
# Auto-detection: whichever target matches the host architecture is native;
# the other target uses a system-provided cross-compiler.
#
# On x86_64 hosts (e.g., amd64 laptop):
#   x86_64 → native (gcc, ar, ld from host PATH)
#   arm64  → cross-aarch64-linux-gnu (prefix: aarch64-linux-gnu-)
#
# On aarch64 hosts (e.g., Apple M1, ARM server):
#   arm64  → native (gcc, ar, ld from host PATH)
#   x86_64 → cross-x86_64-linux-gnu (prefix: x86_64-linux-gnu-)

# Common system bin paths (always available for native tools)
SYS_BIN := /usr/bin

ifeq ($(HOST_ARCH),x86_64)
  TRIPLET_x86_64  := $(HOST_TRIPLET)
  CROSS_x86_64    :=
  TC_PATH_x86_64  := $(SYS_BIN)
  SYSROOT_x86_64  :=

  TRIPLET_arm64   := aarch64-linux-gnu
  CROSS_arm64     := aarch64-linux-gnu-
  TC_PATH_arm64   := $(SYS_BIN)
  SYSROOT_arm64   := /usr/aarch64-linux-gnu

else ifeq ($(HOST_ARCH),aarch64)
  TRIPLET_arm64   := $(HOST_TRIPLET)
  CROSS_arm64     :=
  TC_PATH_arm64   := $(SYS_BIN)
  SYSROOT_arm64   :=

  TRIPLET_x86_64  := x86_64-linux-gnu
  CROSS_x86_64    := x86_64-linux-gnu-
  TC_PATH_x86_64  := $(SYS_BIN)
  SYSROOT_x86_64  := /usr/x86_64-linux-gnu

else ifeq ($(shell uname -s),Darwin)
  # macOS has no Linux toolchain: build targets need a Linux host, but the
  # UTM runner targets (mk/12-utm.mk) work with prebuilt kernel + disk image
else
  $(error Unsupported host architecture: $(HOST_ARCH). Expected x86_64 or aarch64.)
endif

# ── Per-target directories ─────────────────────────────────────────────────
ROOTFS_x86_64           := $(CURDIR)/rootfs/x86_64
ROOTFS_arm64            := $(CURDIR)/rootfs/arm64

BUILD_DIR_x86_64        := $(CURDIR)/sources-build/x86_64
BUILD_DIR_arm64         := $(CURDIR)/sources-build/arm64

# ── Packages ───────────────────────────────────────────────────────────────
# Userland packages, each a submodule sources/<pkg> with build rules in
# mk/04-build-rules.mk, declared per target in mk/05-packages.mk
USERLAND_PKGS := coreutils bash grep sed gawk findutils diffutils gzip tar vim \
                 iproute2 procps-ng util-linux runit dhcpcd openssl openssh

# ── Per-arch facts ─────────────────────────────────────────────────────────
# Everything that differs between the targets lives here; the rules are
# macros over $(TARGETS) and look these up by arch name.
#   TTY_<a>           serial console      KARCH_<a>         kernel ARCH=
#   KERNEL_TARGET_<a> kernel make target  KERNEL_IMAGE_<a>  its path in the tree
#   LDSO_<a>          dynamic linker      MULTIARCH_<a>     Debian library dir name
#   OPENSSL_TARGET_<a> OpenSSL Configure target
TTY_x86_64            := ttyS0
TTY_arm64             := ttyAMA0
KARCH_x86_64          := x86_64
KARCH_arm64           := arm64
KERNEL_TARGET_x86_64  := bzImage
KERNEL_TARGET_arm64   := Image.gz
KERNEL_IMAGE_x86_64   := arch/x86/boot/bzImage
KERNEL_IMAGE_arm64    := arch/arm64/boot/Image.gz
LDSO_x86_64           := /lib64/ld-linux-x86-64.so.2
LDSO_arm64            := /lib/ld-linux-aarch64.so.1
MULTIARCH_x86_64      := x86_64-linux-gnu
MULTIARCH_arm64       := aarch64-linux-gnu
OPENSSL_TARGET_x86_64 := linux-x86_64
OPENSSL_TARGET_arm64  := linux-aarch64

# Built kernel image of an arch: $(call KERNEL_OUT,<arch>)
KERNEL_OUT = $(BUILD_DIR_$(1))/linux-libre/$(KERNEL_IMAGE_$(1))

# ── Shared directories ─────────────────────────────────────────────────────
SOURCES_DIR          := $(CURDIR)/sources
SOURCES_PATCHED_DIR  := $(CURDIR)/sources-patched
SOURCES_PATCHES_DIR  := $(CURDIR)/sources-patches
GNULIB_DIR           := $(SOURCES_DIR)/gnulib
LINUX_LIBRE_DIR     := $(SOURCES_DIR)/linux-libre

# ── Kernel config paths (in project root, tracked by git) ─────────────────
KERNEL_CONFIG_x86_64 := $(CURDIR)/kernel-x86_64.config
KERNEL_CONFIG_arm64  := $(CURDIR)/kernel-arm64.config

FAKE_BIN            := $(CURDIR)/build/fake-bin
FAKE_BIN_PATH       := $(FAKE_BIN):$(PATH)
export PATH         := $(FAKE_BIN):/usr/bin:$(PATH)

PARALLEL            := -j$$(nproc)
STRIP               := 1

# ── Logging ────────────────────────────────────────────────────────────────
# make <target> LOG=1  →  tee all output to build-logs/<target>.log
# Example: make ARCH=x86_64 build-coreutils LOG=1 → build-logs/build-coreutils.log
LOG_DIR := $(CURDIR)/build-logs

ifdef LOG
GOAL := $(or $(MAKECMDGOALS),make)
LOG_FILE := $(LOG_DIR)/$(GOAL).log
$(shell mkdir -p "$(LOG_DIR)")
export LOG_FILE
SHELL := $(CURDIR)/mk/tee-log.sh
endif

# ── Common build flags ─────────────────────────────────────────────────────
COMMON_CFLAGS   := -O2 -pipe -fomit-frame-pointer -s
COMMON_LDFLAGS  := -s -Wl,--as-needed,-z,relro,-z,now

USERLAND_CONFIG := \
    --prefix=/usr \
    --disable-nls \
    --disable-silent-rules

# Per-package/architecture extra configure flags
# Usage: $(PKG)_CONFIGURE_$(ARCH) = --extra-flag
# The variable name is constructed from the package name (with hyphens) and arch:
#   $$($$(1)_CONFIGURE_$(2)) in build macros
procps-ng_CONFIGURE_arm64 := --without-ncurses
# util-linux: skip chown/chgrp/setuid in "make install" (needs root; the build
# runs as a normal user and installs into a DESTDIR)
# No Python bindings (the image has no Python). Cross builds: no ncurses either,
# configure would find the build host's (pkg-config) and fail to link -ltinfo
UTIL_LINUX_CONFIGURE = --disable-makeinstall-chown --disable-makeinstall-setuid \
    --without-python $(if $(CROSS_$(1)),--without-ncursesw --without-ncurses --without-tinfo)
util-linux_CONFIGURE_x86_64 := $(call UTIL_LINUX_CONFIGURE,x86_64)
util-linux_CONFIGURE_arm64  := $(call UTIL_LINUX_CONFIGURE,arm64)
