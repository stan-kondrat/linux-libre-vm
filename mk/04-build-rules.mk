# ═════════════════════════════════════════════════════════════════════════════
# Userland package build macros (per-target)
# ═════════════════════════════════════════════════════════════════════════════

# ── HOST_FLAG(target) ─────────────────────────────────────────────────────
# Returns the --host= flag for configure
HOST_FLAG  = --host=$(TRIPLET_$(1))

# ── DESTDIR_FOR(target) ───────────────────────────────────────────────────
# Returns DESTDIR= for install
DESTDIR_FOR = DESTDIR=$(ROOTFS_$(1))

# ── GIT_CONFIGURE_RULES_PKG(pkg, target) ──────────────────────────────────
# For: bash, gawk
# These packages have a simple ./configure with --srcdir support.
# Sources stay in sources-patched/; build happens in sources-build/<target>/.

define GIT_CONFIGURE_RULES_PKG
$(eval $(call COPY_PKG,$(1),$(2)))

build-$(1)-$(2): $$(BUILD_DIR_$(2))/$(1)/.copied | toolchain-$(2)
	@echo "=== Building $(1) for $(2) ==="
	mkdir -p "$$(BUILD_DIR_$(2))/$(1)"
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
		"$$(SOURCES_PATCHED_DIR)/$(1)"/configure \
			$(call HOST_FLAG,$(2)) \
			$(USERLAND_CONFIG) \
			CFLAGS="$(COMMON_CFLAGS)" \
			LDFLAGS="$(COMMON_LDFLAGS)" || exit 1
	PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" $$(MAKE) $(PARALLEL) -C "$$(BUILD_DIR_$(2))/$(1)"
	@echo "=== $(1) built ($(2)) ==="

install-$(1)-$(2): build-$(1)-$(2)
	$$(MAKE) -C "$$(BUILD_DIR_$(2))/$(1)" $(call DESTDIR_FOR,$(2)) install
endef

# ── GIT_AUTORECONF_RULES_PKG(pkg, target, version) ────────────────────────
# For: procps-ng, util-linux
# These packages need a per-target copy for autoreconf, then in-tree build.

define GIT_AUTORECONF_RULES_PKG
$(eval $(call COPY_PKG,$(1),$(2)))

build-$(1)-$(2): fake-bin $$(BUILD_DIR_$(2))/$(1)/.copied | toolchain-$(2)
	@echo "=== Building $(1) for $(2) (autoreconf) ==="
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  mkdir -p build-aux m4 po && \
	  echo "$(3)" > .tarball-version && \
	  printf '#!/bin/sh\ncat .tarball-version\n' > build-aux/git-version-gen && chmod +x build-aux/git-version-gen && \
	  printf 'AC_DEFUN([AM_GNU_GETTEXT_VERSION],[])\nAC_DEFUN([AM_GNU_GETTEXT],[])\nAC_DEFUN([AM_NLS],[])\n' > m4/gettext-stubs.m4 && \
	  printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile.in.in && \
	  PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" AUTOPOINT=true autoreconf -fi
	"$$(BUILD_DIR_$(2))/$(1)"/configure \
	    $(call HOST_FLAG,$(2)) \
	    $(USERLAND_CONFIG) \
	    CFLAGS="$(COMMON_CFLAGS)" LDFLAGS="$(COMMON_LDFLAGS)" || \
	  ( mkdir -p po && printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile && \
	    "$$(BUILD_DIR_$(2))/$(1)"/configure \
	      $(call HOST_FLAG,$(2)) \
	      $(USERLAND_CONFIG) \
	      CFLAGS="$(COMMON_CFLAGS)" LDFLAGS="$(COMMON_LDFLAGS)" )
	PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" $$(MAKE) $(PARALLEL) -C "$$(BUILD_DIR_$(2))/$(1)"
	@echo "=== $(1) built ($(2)) ==="

install-$(1)-$(2): build-$(1)-$(2)
	$$(MAKE) -C "$$(BUILD_DIR_$(2))/$(1)" $(call DESTDIR_FOR,$(2)) install
endef

# ── GIT_GNULIB_RULES_PKG(pkg, target, version) ────────────────────────────
# For: coreutils, grep, sed, findutils, diffutils, gzip, tar
# These packages need gnulib bootstrap + per-target copy, then in-tree build.

define GIT_GNULIB_RULES_PKG
$(eval $(call COPY_PKG,$(1),$(2)))

build-$(1)-$(2): fake-bin $$(BUILD_DIR_$(2))/$(1)/.copied | toolchain-$(2)
	@echo "=== Building $(1) for $(2) (gnulib bootstrap, in-tree) ==="
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  mkdir -p po build-aux && \
	  touch ABOUT-NLS ChangeLog po/Makevars.template && \
	  printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile.in.in && \
	  echo "$(3)" > .tarball-version && \
	  printf '#!/bin/sh\ncat .tarball-version\n' > build-aux/git-version-gen && chmod +x build-aux/git-version-gen && \
	  PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" GNULIB_SRCDIR="$(GNULIB_DIR)" ./bootstrap --gen 2>&1 | \
	    grep -v "^  \|Copying\|running\|autoreconf:\|making\|ln -fs"
	mkdir -p "$$(BUILD_DIR_$(2))/$(1)/m4" 2>/dev/null
	printf '%s\n' \
	  'AC_DEFUN([AM_GNU_GETTEXT_VERSION],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT_REQUIRE_VERSION],[])' \
	  'AC_DEFUN([AM_NLS],[])' \
	  'AC_DEFUN([gl_TYPE_WINT_T_PREREQ])' \
	  'AC_DEFUN([AM_ICONV])' \
	  > "$$(BUILD_DIR_$(2))/$(1)/m4/gettext-stubs.m4"
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/m4/gnulib-cache.m4" ]; then \
	  cat "$$(BUILD_DIR_$(2))/$(1)/m4/gettext-stubs.m4" >> "$$(BUILD_DIR_$(2))/$(1)/m4/gnulib-cache.m4"; \
	fi
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/thread-creators.gperf" ]; then \
	  awk '/^[a-zA-Z_]/ { print "static int never_use_" $$$$1 "(void) { return 1; }" }' \
	    "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/thread-creators.gperf" \
	    > "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/thread-creators.h"; \
	fi
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" AUTOPOINT=true autoreconf -fi 2>/dev/null || true
	for f in config.guess config.sub install-sh mkinstalldirs compile missing depcomp; do \
	  if [ ! -f "$$(BUILD_DIR_$(2))/$(1)/build-aux/$$$$f" ]; then \
	    for s in "$(GNULIB_DIR)/build-aux" /usr/share/automake-1.16 /usr/share/libtool/build-aux /usr/share/misc; do \
	      if [ -f "$$$$s/$$$$f" ]; then \
	        cp "$$$$s/$$$$f" "$$(BUILD_DIR_$(2))/$(1)/build-aux/$$$$f"; \
	        break; \
	      fi; \
	    done; \
	  fi; \
	done
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  ./configure \
	    $(call HOST_FLAG,$(2)) \
	    --prefix=/usr --disable-nls --disable-silent-rules \
	    CFLAGS="$(COMMON_CFLAGS)" LDFLAGS="$(COMMON_LDFLAGS)"
	PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" $$(MAKE) $(PARALLEL) -C "$$(BUILD_DIR_$(2))/$(1)"
	@echo "=== $(1) built ($(2)) ==="

install-$(1)-$(2): build-$(1)-$(2)
	$$(MAKE) -C "$$(BUILD_DIR_$(2))/$(1)" $(call DESTDIR_FOR,$(2)) install
endef

# ═════════════════════════════════════════════════════════════════════════════
# Custom build macros (per-target)
# ═════════════════════════════════════════════════════════════════════════════

# ── tar (gnulib + paxutils) ───────────────────────────────────────────────

define TAR_BUILD_RULES
$$(eval $$(call COPY_PKG,tar,$(1)))

build-tar-$(1): fake-bin $$(BUILD_DIR_$(1))/tar/.copied | toolchain-$(1)
	@echo "=== Building tar for $(1) (gnulib bootstrap, in-tree) ==="
	cd "$$(BUILD_DIR_$(1))/tar" && \
	  mkdir -p po build-aux && \
	  touch ABOUT-NLS ChangeLog po/Makevars.template && \
	  printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile.in.in && \
	  echo "1.35" > .tarball-version && \
	  printf '#!/bin/sh\ncat .tarball-version\n' > build-aux/git-version-gen && chmod +x build-aux/git-version-gen && \
	  PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" GNULIB_SRCDIR="$$(GNULIB_DIR)" ./bootstrap --gen 2>&1 | \
	    grep -v "^  \|Copying\|running\|autoreconf:\|making\|ln -fs"
	mkdir -p "$$(BUILD_DIR_$(1))/tar/m4" 2>/dev/null
	printf '%s\n' \
	  'AC_DEFUN([AM_GNU_GETTEXT_VERSION],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT_REQUIRE_VERSION],[])' \
	  'AC_DEFUN([AM_NLS],[])' \
	  'AC_DEFUN([gl_TYPE_WINT_T_PREREQ])' \
	  'AC_DEFUN([AM_ICONV])' \
	  > "$$(BUILD_DIR_$(1))/tar/m4/gettext-stubs.m4"
	if [ -f "$$(BUILD_DIR_$(1))/tar/m4/gnulib-cache.m4" ]; then \
	  cat "$$(BUILD_DIR_$(1))/tar/m4/gettext-stubs.m4" >> "$$(BUILD_DIR_$(1))/tar/m4/gnulib-cache.m4"; \
	fi
	printf '# Stub Make.rules\nSUFFIXES:\n' > "$$(BUILD_DIR_$(1))/tar/Make.rules"
	if [ -f "$$(BUILD_DIR_$(1))/tar/gnulib-tests/thread-creators.gperf" ]; then \
	  awk '/^[a-zA-Z_]/ { print "static int never_use_" $$$$1 "(void) { return 1; }" }' \
	    "$$(BUILD_DIR_$(1))/tar/gnulib-tests/thread-creators.gperf" \
	    > "$$(BUILD_DIR_$(1))/tar/gnulib-tests/thread-creators.h"; \
	fi
	cd "$$(BUILD_DIR_$(1))/tar" && \
	  PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" AUTOPOINT=true autoreconf -fi 2>&1
	for f in config.guess config.sub install-sh mkinstalldirs compile missing depcomp; do \
	  if [ ! -f "$$(BUILD_DIR_$(1))/tar/build-aux/$$$$f" ]; then \
	    for s in "$$(GNULIB_DIR)/build-aux" /usr/share/automake-1.16 /usr/share/libtool/build-aux /usr/share/misc; do \
	      if [ -f "$$$$s/$$$$f" ]; then \
	        cp "$$$$s/$$$$f" "$$(BUILD_DIR_$(1))/tar/build-aux/$$$$f"; \
	        break; \
	      fi; \
	    done; \
	  fi; \
	done
	cd "$$(BUILD_DIR_$(1))/tar" && \
	  ./configure \
	    $$(call HOST_FLAG,$(1)) \
	    --prefix=/usr --disable-nls --disable-silent-rules \
	    CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)"
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/tar"
	@echo "=== tar built ($(1)) ==="

install-tar-$(1): build-tar-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/tar" $$(call DESTDIR_FOR,$(1)) install
endef

# ── iproute2 (custom configure) ───────────────────────────────────────────

define IPROUTE2_BUILD_RULES
$$(eval $$(call COPY_PKG,iproute2,$(1)))

build-iproute2-$(1): $$(BUILD_DIR_$(1))/iproute2/.copied | toolchain-$(1)
	@echo "=== Building iproute2 for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/iproute2" && \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  ./configure --prefix=/usr
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  CFLAGS="-O2 -pipe -fomit-frame-pointer -s" LDFLAGS="-s -Wl,--as-needed,-z,relro,-z,now" \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/iproute2"
	@echo "=== iproute2 built ($(1)) ==="

install-iproute2-$(1): build-iproute2-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/iproute2" DESTDIR="$$(ROOTFS_$(1))" install
endef

# ── dhcpcd (custom configure) ─────────────────────────────────────────────

define DHCPCD_BUILD_RULES
$$(eval $$(call COPY_PKG,dhcpcd,$(1)))

build-dhcpcd-$(1): $$(BUILD_DIR_$(1))/dhcpcd/.copied | toolchain-$(1)
	@echo "=== Building dhcpcd for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/dhcpcd" && \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)" \
	  ./configure --prefix=/usr --sysconfdir=/etc --datadir=/usr/share \
	    --libexecdir=/usr/libexec --dbdir=/var/db/dhcpcd --rundir=/var/run/dhcpcd
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/dhcpcd"
	@echo "=== dhcpcd built ($(1)) ==="

install-dhcpcd-$(1): build-dhcpcd-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/dhcpcd" DESTDIR="$$(ROOTFS_$(1))" install
endef

# ── vim (custom configure) ────────────────────────────────────────────────

define VIM_BUILD_RULES
$$(eval $$(call COPY_PKG,vim,$(1)))

build-vim-$(1): $$(BUILD_DIR_$(1))/vim/.copied | toolchain-$(1)
	@echo "=== Building vim for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/vim/src" && ./configure \
		--prefix=/usr --with-features=tiny --disable-gui \
		--without-x --disable-netbeans --disable-channel \
		--disable-gpm --disable-acl --disable-nls \
		--disable-darwin --disable-smack --disable-selinux \
		--disable-xsmp --disable-xsmp-interact \
		--enable-gui=no --without-luajit \
		--with-compiledby="linux-vm" \
		--host=$$(TRIPLET_$(1)) \
		vim_cv_toupper_broken=no \
		vim_cv_terminfo=yes \
		vim_cv_tty_group=world \
		ac_cv_sizeof_int=4 \
		CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)"
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/vim/src"
	@echo "=== vim built ($(1)) ==="

install-vim-$(1): build-vim-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/vim" DESTDIR="$$(ROOTFS_$(1))" install
endef

# ── runit (custom build — package/compile) ────────────────────────────────

define RUNIT_BUILD_RULES
$$(eval $$(call COPY_PKG,runit,$(1)))

build-runit-$(1): $$(BUILD_DIR_$(1))/runit/.copied | toolchain-$(1)
	@echo "=== Building runit for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/runit" && \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar RANLIB=$$(CROSS_$(1))ranlib \
	  package/compile
	@echo "=== runit built ($(1)) ==="

install-runit-$(1): build-runit-$(1)
	mkdir -p "$$(ROOTFS_$(1))/sbin"
	for prog in runsv runsvdir runsvchpfd chpst sv; do \
		[ -f "$$(BUILD_DIR_$(1))/runit/command/$$$$prog" ] && cp "$$(BUILD_DIR_$(1))/runit/command/$$$$prog" "$$(ROOTFS_$(1))/sbin/"; \
	done
endef
