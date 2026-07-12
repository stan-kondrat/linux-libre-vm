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
TRIPLET_x86_64  := x86_64-linux-gnu
TRIPLET_arm64   := aarch64-linux-gnu

CROSS_x86_64     = $(TOOLCHAIN_PREFIX)/x86_64/bin/x86_64-linux-gnu-
CROSS_arm64      = $(TOOLCHAIN_PREFIX)/arm64/bin/aarch64-linux-gnu-

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

# ── Cross-compiler toolchain ───────────────────────────────────────────────
TOOLCHAIN_PREFIX    := $(CURDIR)/toolchain
TC_PATH_x86_64      := $(TOOLCHAIN_PREFIX)/x86_64/bin
TC_PATH_arm64       := $(TOOLCHAIN_PREFIX)/arm64/bin
SYSROOT_x86_64      := $(TOOLCHAIN_PREFIX)/x86_64/sysroot
SYSROOT_arm64       := $(TOOLCHAIN_PREFIX)/arm64/sysroot

PARALLEL            := -j$$(nproc)
STRIP               := 1

# ── Logging ────────────────────────────────────────────────────────────────
# make <target> LOG=1  →  tee all output to build-logs/<target>.log
# Example: make build-coreutils-x86_64 LOG=1 → build-logs/build-coreutils-x86_64.log
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
