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
USERLAND_PKGS := ncurses coreutils bash grep sed gawk findutils diffutils gzip tar vim \
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
# Hardening: stack protector, fortified libc calls, full RELRO. The source
# path is mapped to "." so it does not end up in the binaries.
COMMON_CFLAGS   := -O2 -pipe -fomit-frame-pointer -fstack-protector-strong \
                   -D_FORTIFY_SOURCE=2 -ffile-prefix-map=$(CURDIR)=.
COMMON_LDFLAGS  := -s -Wl,--as-needed,-z,relro,-z,now

# Timestamps written into the build output (images, archives) come from the
# last commit, not the build time
SOURCE_DATE_EPOCH ?= $(shell git -C "$(CURDIR)" log -1 --format=%ct 2>/dev/null || echo 0)
export SOURCE_DATE_EPOCH

USERLAND_CONFIG := \
    --prefix=/usr \
    --disable-nls \
    --disable-silent-rules

# Per-package configure flags: <pkg>_CONFIGURE (all arches) and
# <pkg>_CONFIGURE_<arch>, used as $($(1)_CONFIGURE) $($(1)_CONFIGURE_$(2))
# in the build macros.
#
# Optional features are switched off here explicitly. Left to configure, they
# depend on what the build host has installed (OpenSSL, GMP, PAM, readline,
# PCRE2, libelf, libcrypt, zlib ...): a native build picked them up and a
# cross build did not, so the two images differed, and the host's libraries
# were copied in.
coreutils_CONFIGURE := --with-openssl=no --without-libgmp --disable-acl --disable-xattr \
    --disable-libcap --disable-libsmack --without-selinux
grep_CONFIGURE      := --disable-perl-regexp
sed_CONFIGURE       := --disable-acl --without-selinux
findutils_CONFIGURE := --without-selinux
tar_CONFIGURE       := --without-posix-acls --without-selinux --without-xattrs
gawk_CONFIGURE      := --disable-mpfr --without-readline --disable-extensions
procps-ng_CONFIGURE := --without-systemd --without-elogind --disable-static
# util-linux: skip chown/chgrp/setuid in "make install" (needs root; the build
# runs as a normal user and installs into a DESTDIR). No login/su/chfn/chsh/
# runuser (they need PAM; the console logs in as root directly).
util-linux_CONFIGURE := --disable-makeinstall-chown --disable-makeinstall-setuid \
    --without-python --without-readline --without-systemd --without-udev \
    --without-libmagic --without-cap-ng --without-econf --without-selinux \
    --without-audit --without-smack --without-btrfs --without-user \
    --disable-login --disable-su --disable-chfn-chsh --disable-runuser \
    --disable-sulogin --disable-newgrp --disable-pam-lastlog2 \
    --disable-bash-completion --disable-cramfs --disable-static

# ncurses: bash, vim, procps-ng and util-linux use the staged pinned ncurses
# (mk/04-build-rules.mk), never the build host's, natively and cross.
#   NCURSES_ENV_<a>      configure arguments: its headers, and pkg-config
#                        restricted to its ncursesw.pc (paths under the stage)
#   NCURSES_LDFLAGS_<a>  -L to its library, added to LDFLAGS
#   <pkg>_LDFLAGS_<a>    per-package extra LDFLAGS (build macros)
# bash: bash_cv_termcap_lib, or its configure takes the host's -ltinfo first.
NCURSES_USERS := bash vim procps-ng util-linux
$(foreach a,$(TARGETS),$(eval NCURSES_STAGE_$(a) := $(BUILD_DIR_$(a))/ncurses-stage))
$(foreach a,$(TARGETS),$(eval NCURSES_ENV_$(a) := CPPFLAGS=-I$(NCURSES_STAGE_$(a))/usr/include \
    PKG_CONFIG_LIBDIR=$(NCURSES_STAGE_$(a))/usr/lib/pkgconfig PKG_CONFIG_SYSROOT_DIR=$(NCURSES_STAGE_$(a))))
$(foreach a,$(TARGETS),$(eval NCURSES_LDFLAGS_$(a) := -L$(NCURSES_STAGE_$(a))/usr/lib))
bash_CONFIGURE := bash_cv_termcap_lib=libncursesw
$(foreach a,$(TARGETS),$(foreach p,bash procps-ng util-linux,\
    $(eval $(p)_CONFIGURE_$(a) := $(NCURSES_ENV_$(a)))\
    $(eval $(p)_LDFLAGS_$(a) := $(NCURSES_LDFLAGS_$(a)))))
# util-linux looks for ncurses*-config scripts on PATH before pkg-config (the
# build host's, pointing at its -lncursesw -ltinfo): disabled. Its tinfo
# check finds tinfow.pc in the stage (mk/04-build-rules.mk).
$(foreach a,$(TARGETS),$(eval util-linux_CONFIGURE_$(a) += \
    NCURSESW6_CONFIG=false NCURSESW5_CONFIG=false NCURSES6_CONFIG=false NCURSES5_CONFIG=false))
