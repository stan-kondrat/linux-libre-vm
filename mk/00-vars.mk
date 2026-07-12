# ═════════════════════════════════════════════════════════════════════════════
# Variables, directories, and common flags
# ═════════════════════════════════════════════════════════════════════════════

.DEFAULT_GOAL := help

# ── Host detection ──────────────────────────────────────────────────────────
HOST_ARCH       := $(shell gcc -dumpmachine | sed 's/-.*//')
HOST_TRIPLET    := $(shell gcc -dumpmachine)

# ── Target architectures ────────────────────────────────────────────────────
TARGETS         := x86_64 arm64

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

else
  $(error Unsupported host architecture: $(HOST_ARCH). Expected x86_64 or aarch64.)
endif

# ── Per-target directories ─────────────────────────────────────────────────
ROOTFS_x86_64           := $(CURDIR)/rootfs/x86_64
ROOTFS_arm64            := $(CURDIR)/rootfs/arm64

BUILD_DIR_x86_64        := $(CURDIR)/sources-build/x86_64
BUILD_DIR_arm64         := $(CURDIR)/sources-build/arm64

# ── Shared directories ─────────────────────────────────────────────────────
SOURCES_DIR          := $(CURDIR)/sources
SOURCES_PATCHED_DIR  := $(CURDIR)/sources-patched
SOURCES_PATCHES_DIR  := $(CURDIR)/sources-patches
GNULIB_DIR           := $(SOURCES_DIR)/gnulib
LINUX_LIBRE_DIR     := $(SOURCES_DIR)/linux-libre

FAKE_BIN            := $(CURDIR)/build/fake-bin
FAKE_BIN_PATH       := $(FAKE_BIN):$(PATH)

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
