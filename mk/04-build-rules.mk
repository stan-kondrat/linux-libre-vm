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

build-$(1)-$(2): $$(BUILD_DIR_$(2))/$(1)/.built

$$(BUILD_DIR_$(2))/$(1)/.built: $$(BUILD_DIR_$(2))/$(1)/.copied
	@echo "=== Building $(1) for $(2) ==="
	mkdir -p "$$(BUILD_DIR_$(2))/$(1)"
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
		"$$(SOURCES_PATCHED_DIR)/$(1)"/configure \
			$(call HOST_FLAG,$(2)) \
			$(USERLAND_CONFIG) $$($(1)_CONFIGURE) $$($(1)_CONFIGURE_$(2)) \
			CFLAGS="$(COMMON_CFLAGS)" \
			LDFLAGS="$(COMMON_LDFLAGS) $$($(1)_LDFLAGS_$(2))" || exit 1
	# Cross-compilation: stub help2man (cross binaries can't run on host)
	if [ -n "$(CROSS_$(2))" ] && [ -f "$$(BUILD_DIR_$(2))/$(1)/man/help2man" ]; then \
	  printf '#!/bin/sh\nfor f; do :; done\n' > "$$(BUILD_DIR_$(2))/$(1)/man/help2man"; \
	  chmod +x "$$(BUILD_DIR_$(2))/$(1)/man/help2man"; \
	fi
	# Gawk fix: command.c must use bison -p zz prefix (ylwrap overrides specific rule)
	if [ "$(1)" = "gawk" ] && [ -f "$$(BUILD_DIR_$(2))/$(1)/command.y" ]; then \
	  bison -y -p zz -o "$$(BUILD_DIR_$(2))/$(1)/command.c" "$$(BUILD_DIR_$(2))/$(1)/command.y" 2>/dev/null; \
	  touch "$$(BUILD_DIR_$(2))/$(1)/command.c"; \
	fi
	# Gawk fix: use the awklib/eg sources shipped in git. If a checkout leaves
	# doc/gawk.texi newer than awklib/stamp-eg, make wipes eg/ and re-extracts
	# it with the host gawk, which loses pwcat.c/grcat.c on CI runners
	if [ "$(1)" = "gawk" ] && [ -f "$$(SOURCES_PATCHED_DIR)/$(1)/awklib/stamp-eg" ]; then \
	  touch "$$(SOURCES_PATCHED_DIR)/$(1)/awklib/stamp-eg"; \
	fi
	PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" $$(MAKE) $(PARALLEL) -C "$$(BUILD_DIR_$(2))/$(1)"
	@touch "$$@"
	@echo "=== $(1) built ($(2)) ==="

install-$(1)-$(2): build-$(1)-$(2)
	$$(MAKE) -C "$$(BUILD_DIR_$(2))/$(1)" $(call DESTDIR_FOR,$(2)) install
endef

# ── GIT_AUTORECONF_RULES_PKG(pkg, target, version) ────────────────────────
# For: procps-ng, util-linux
# These packages need a per-target copy for autoreconf, then in-tree build.

define GIT_AUTORECONF_RULES_PKG
$(eval $(call COPY_PKG,$(1),$(2)))

build-$(1)-$(2): $$(BUILD_DIR_$(2))/$(1)/.built

$$(BUILD_DIR_$(2))/$(1)/.built: $$(BUILD_DIR_$(2))/$(1)/.copied | $(FAKE_BIN)/.stamp
	@echo "=== Building $(1) for $(2) (autoreconf) ==="
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  mkdir -p build-aux m4 po && \
	  echo "$(3)" > .tarball-version && \
	  printf 'AC_DEFUN([AM_GNU_GETTEXT_VERSION],[])\nAC_DEFUN([AM_GNU_GETTEXT],[])\nAC_DEFUN([AM_NLS],[])\n' > m4/gettext-stubs.m4 && \
	  printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile.in.in && \
	  PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" AUTOPOINT=true autoreconf -fi
	cd "$$(BUILD_DIR_$(2))/$(1)" && ./configure \
	    $(call HOST_FLAG,$(2)) \
	    $(USERLAND_CONFIG) --disable-liblastlog2 \
	    $$($(1)_CONFIGURE) $$($(1)_CONFIGURE_$(2)) \
	    CFLAGS="$(COMMON_CFLAGS)" LDFLAGS="$(COMMON_LDFLAGS) $$($(1)_LDFLAGS_$(2))"
	printf '%s\n' 'all:' 'install:' 'clean:' '.PHONY: all install clean' > "$$(BUILD_DIR_$(2))/$(1)/po/Makefile" 2>/dev/null || true
	# Cross-compilation: stub help2man (cross binaries can't run on host)
	if [ -n "$(CROSS_$(2))" ] && [ -f "$$(BUILD_DIR_$(2))/$(1)/man/help2man" ]; then \
	  printf '#!/bin/sh\nfor f; do :; done\n' > "$$(BUILD_DIR_$(2))/$(1)/man/help2man"; \
	  chmod +x "$$(BUILD_DIR_$(2))/$(1)/man/help2man"; \
	fi
	PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" $$(MAKE) $(PARALLEL) -C "$$(BUILD_DIR_$(2))/$(1)"
	@touch "$$@"
	@echo "=== $(1) built ($(2)) ==="

install-$(1)-$(2): build-$(1)-$(2)
	$$(MAKE) -C "$$(BUILD_DIR_$(2))/$(1)" $(call DESTDIR_FOR,$(2)) install
endef

# ── GIT_GNULIB_RULES_PKG(pkg, target, version) ────────────────────────────
# For: coreutils, grep, sed, findutils, diffutils, gzip, tar
# These packages need gnulib bootstrap + per-target copy, then in-tree build.

define GIT_GNULIB_RULES_PKG
$(eval $(call COPY_PKG,$(1),$(2)))

build-$(1)-$(2): $$(BUILD_DIR_$(2))/$(1)/.built

$$(BUILD_DIR_$(2))/$(1)/.built: $$(BUILD_DIR_$(2))/$(1)/.copied | $(FAKE_BIN)/.stamp
	@echo "=== Building $(1) for $(2) (gnulib bootstrap, in-tree) ==="
	# Add gettext stubs BEFORE bootstrap so its autoreconf succeeds
	mkdir -p "$$(BUILD_DIR_$(2))/$(1)/m4" 2>/dev/null
	printf '%s\n' \
	  'AC_DEFUN([AM_GNU_GETTEXT_VERSION],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT_REQUIRE_VERSION],[])' \
	  'AC_DEFUN([AM_NLS],[])' \
	  'AC_DEFUN([gl_TYPE_WINT_T_PREREQ])' \
	  'AC_DEFUN([AM_ICONV])' \
	  'AC_DEFUN([gl_EARLY],[])' \
	  'AC_DEFUN([gl_INIT],[])' \
	  > "$$(BUILD_DIR_$(2))/$(1)/m4/gettext-stubs.m4"
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  mkdir -p po build-aux && \
	  touch ABOUT-NLS ChangeLog po/Makevars.template && \
	  printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile.in.in && \
	  echo "$(3)" > .tarball-version && \
	  export PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" GNULIB_SRCDIR="$(GNULIB_DIR)" && \
	  { ./bootstrap --gen 2>&1 || ./bootstrap --skip-po --no-git 2>&1; } | \
	    grep -v "^  \|Copying\|running\|autoreconf:\|making\|ln -fs"
	# Bootstrap may symlink git-version-gen to GNULIB_SRCDIR. Remove and rewrite.
	rm -f "$$(BUILD_DIR_$(2))/$(1)/build-aux/git-version-gen"
	printf '#!/bin/sh\ncat .tarball-version\n' > "$$(BUILD_DIR_$(2))/$(1)/build-aux/git-version-gen"
	chmod +x "$$(BUILD_DIR_$(2))/$(1)/build-aux/git-version-gen"
	# Fix gnulib-tests/gnulib.mk: newer automake requires AM_CFLAGS = before +=
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/gnulib.mk" ]; then \
	  sed -i '1iAM_CFLAGS =' "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/gnulib.mk"; \
	fi
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/lib/gnulib.mk" ]; then \
	  sed -i '1iAM_CFLAGS =' "$$(BUILD_DIR_$(2))/$(1)/lib/gnulib.mk"; \
	fi
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/thread-creators.gperf" ]; then \
	  awk '/^[a-zA-Z_]/ { print "static int never_use_" $$$$1 "(void) { return 1; }" }' \
	    "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/thread-creators.gperf" \
	    > "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/thread-creators.h"; \
	fi
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
	  PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" AUTOPOINT=true autoreconf -fi 2>&1 || true
	# Some gnulib-tests/Makefile.am files have ordering issues with newer
	# automake (AM_CFLAGS += before =). Generate a minimal Makefile.in.
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/Makefile.am" ] && \
	   [ ! -f "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/Makefile.in" ]; then \
	  printf '%s\n' '# dummy' 'all:' 'install:' 'clean:' '.PHONY: all install clean' \
	    > "$$(BUILD_DIR_$(2))/$(1)/gnulib-tests/Makefile.in"; \
	fi
	cd "$$(BUILD_DIR_$(2))/$(1)" && \
	  ./configure \
	    $(call HOST_FLAG,$(2)) \
	    --prefix=/usr --disable-nls --disable-silent-rules \
	    $$($(1)_CONFIGURE) $$($(1)_CONFIGURE_$(2)) \
	    CFLAGS="$(COMMON_CFLAGS)" LDFLAGS="$(COMMON_LDFLAGS)"
	# Ensure po/Makefile exists (--disable-nls still recurses into po/)
	printf '%s\n' 'all:' 'install:' 'clean:' '.PHONY: all install clean' > "$$(BUILD_DIR_$(2))/$(1)/po/Makefile" 2>/dev/null || true
	# Cross-compilation: compile build-time host tools natively
	if [ -f "$$(BUILD_DIR_$(2))/$(1)/src/make-prime-list.c" ]; then \
	  gcc -I"$$(BUILD_DIR_$(2))/$(1)" -I"$$(BUILD_DIR_$(2))/$(1)/lib" -O2 \
	    -o "$$(BUILD_DIR_$(2))/$(1)/src/make-prime-list" "$$(BUILD_DIR_$(2))/$(1)/src/make-prime-list.c"; \
	  "$$(BUILD_DIR_$(2))/$(1)/src/make-prime-list" 5000 > "$$(BUILD_DIR_$(2))/$(1)/src/primes.h"; \
	  chmod a-w "$$(BUILD_DIR_$(2))/$(1)/src/primes.h"; \
	fi
	# Cross-compilation: stub help2man (cross binaries cannot run on host)
	if [ -n "$(CROSS_$(2))" ]; then \
	  if [ -f "$$(BUILD_DIR_$(2))/$(1)/man/help2man" ]; then \
	    printf '#!/bin/sh\nfor f; do :; done\n' > "$$(BUILD_DIR_$(2))/$(1)/man/help2man"; \
	    chmod +x "$$(BUILD_DIR_$(2))/$(1)/man/help2man"; \
	  fi; \
	fi
	PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" $$(MAKE) $(PARALLEL) -C "$$(BUILD_DIR_$(2))/$(1)"
	@touch "$$@"
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

build-tar-$(1): $$(BUILD_DIR_$(1))/tar/.built

$$(BUILD_DIR_$(1))/tar/.built: $$(BUILD_DIR_$(1))/tar/.copied | $(FAKE_BIN)/.stamp
	@echo "=== Building tar for $(1) (gnulib bootstrap, in-tree) ==="
	# Ensure the paxutils submodule is populated (gnulib comes from GNULIB_SRCDIR)
	if [ ! -f "$(SOURCES_DIR)/tar/paxutils/DISTFILES" ]; then \
	  "$(CURDIR)/scripts/fetch-submodules.sh" sources/tar/paxutils; \
	fi
	# Re-copy sources if paxutils was just populated
	if [ ! -f "$$(BUILD_DIR_$(1))/tar/paxutils/DISTFILES" ]; then \
	  rsync -a --exclude=.git "$(SOURCES_DIR)/tar/" "$$(BUILD_DIR_$(1))/tar/" 2>/dev/null || true; \
	fi
	# Add gettext stubs BEFORE bootstrap so its autoreconf succeeds
	mkdir -p "$$(BUILD_DIR_$(1))/tar/m4" 2>/dev/null
	printf '%s\n' \
	  'AC_DEFUN([AM_GNU_GETTEXT_VERSION],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT],[])' \
	  'AC_DEFUN([AM_GNU_GETTEXT_REQUIRE_VERSION],[])' \
	  'AC_DEFUN([AM_NLS],[])' \
	  'AC_DEFUN([gl_TYPE_WINT_T_PREREQ])' \
	  'AC_DEFUN([AM_ICONV])' \
	  'AC_DEFUN([gl_EARLY],[])' \
	  'AC_DEFUN([gl_INIT],[])' \
	  > "$$(BUILD_DIR_$(1))/tar/m4/gettext-stubs.m4"
	# Create rmt/Makefile.am stub (prevents PU_RMT_COND error)
	mkdir -p "$$(BUILD_DIR_$(1))/tar/rmt"
	printf '%s\n' 'all:' 'install:' 'clean:' '.PHONY: all install clean' > "$$(BUILD_DIR_$(1))/tar/rmt/Makefile.am"
	# Add PU_RMT_COND to configure.ac BEFORE AC_OUTPUT (required by doc/Makefile.am)
	sed -i '/^AC_OUTPUT$$$$/iAM_CONDITIONAL([PU_RMT_COND], [false])' "$$(BUILD_DIR_$(1))/tar/configure.ac"
	printf '# Stub Make.rules\nSUFFIXES:\n' > "$$(BUILD_DIR_$(1))/tar/Make.rules"
	cd "$$(BUILD_DIR_$(1))/tar" && \
	  mkdir -p po build-aux rmt && \
	  touch ABOUT-NLS ChangeLog po/Makevars.template && \
	  printf 'all:\ninstall:\nclean:\n.PHONY: all install clean\n' > po/Makefile.in.in && \
	  echo "1.35" > .tarball-version && \
	  PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" GNULIB_SRCDIR="$$(GNULIB_DIR)" ./bootstrap --gen 2>&1 | \
	    grep -v "^  \|Copying\|running\|autoreconf:\|making\|ln -fs"
	# Bootstrap may symlink git-version-gen to GNULIB_SRCDIR. Remove and rewrite.
	rm -f "$$(BUILD_DIR_$(1))/tar/build-aux/git-version-gen"
	printf '#!/bin/sh\ncat .tarball-version\n' > "$$(BUILD_DIR_$(1))/tar/build-aux/git-version-gen"
	chmod +x "$$(BUILD_DIR_$(1))/tar/build-aux/git-version-gen"
	# Fix gnulib-tests/gnulib.mk: newer automake requires AM_CFLAGS = before +=
	if [ -f "$$(BUILD_DIR_$(1))/tar/gnulib-tests/gnulib.mk" ]; then \
	  sed -i '1iAM_CFLAGS =' "$$(BUILD_DIR_$(1))/tar/gnulib-tests/gnulib.mk"; \
	fi
	if [ -f "$$(BUILD_DIR_$(1))/tar/lib/gnulib.mk" ]; then \
	  sed -i '1iAM_CFLAGS =' "$$(BUILD_DIR_$(1))/tar/lib/gnulib.mk"; \
	fi
	if [ -f "$$(BUILD_DIR_$(1))/tar/m4/gnulib-cache.m4" ]; then \
	  cat "$$(BUILD_DIR_$(1))/tar/m4/gettext-stubs.m4" >> "$$(BUILD_DIR_$(1))/tar/m4/gnulib-cache.m4"; \
	fi
	if [ -f "$$(BUILD_DIR_$(1))/tar/gnulib-tests/thread-creators.gperf" ]; then \
	  awk '/^[a-zA-Z_]/ { print "static int never_use_" $$$$1 "(void) { return 1; }" }' \
	    "$$(BUILD_DIR_$(1))/tar/gnulib-tests/thread-creators.gperf" \
	    > "$$(BUILD_DIR_$(1))/tar/gnulib-tests/thread-creators.h"; \
	fi
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
	printf '%s\n' 'all:' 'install:' 'clean:' '.PHONY: all install clean' > "$$(BUILD_DIR_$(1))/tar/rmt/Makefile.in"
	cd "$$(BUILD_DIR_$(1))/tar" && \
	  PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" AUTOPOINT=true autoreconf -fi 2>&1
	cd "$$(BUILD_DIR_$(1))/tar" && \
	  ./configure \
	    $$(call HOST_FLAG,$(1)) \
	    --prefix=/usr --disable-nls --disable-silent-rules $$(tar_CONFIGURE) \
	    CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)"
	# Ensure po/Makefile exists (--disable-nls still recurses into po/)
	printf '%s\n' 'all:' 'install:' 'clean:' '.PHONY: all install clean' > "$$(BUILD_DIR_$(1))/tar/po/Makefile" 2>/dev/null || true
	# Cross-compilation: compile build-time host tools natively
	if [ -f "$$(BUILD_DIR_$(1))/tar/src/make-prime-list.c" ]; then \
	  gcc -I"$$(BUILD_DIR_$(1))/tar" -I"$$(BUILD_DIR_$(1))/tar/lib" -O2 \
	    -o "$$(BUILD_DIR_$(1))/tar/src/make-prime-list" "$$(BUILD_DIR_$(1))/tar/src/make-prime-list.c"; \
	  "$$(BUILD_DIR_$(1))/tar/src/make-prime-list" 5000 > "$$(BUILD_DIR_$(1))/tar/src/primes.h"; \
	  chmod a-w "$$(BUILD_DIR_$(1))/tar/src/primes.h"; \
	fi
	touch "$$(BUILD_DIR_$(1))/tar/doc/genfile.texi" 2>/dev/null || true
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/tar"
	@touch "$$@"
	@echo "=== tar built ($(1)) ==="

install-tar-$(1): build-tar-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/tar" $$(call DESTDIR_FOR,$(1)) install
endef

# ── iproute2 (custom configure) ───────────────────────────────────────────

define IPROUTE2_BUILD_RULES
$$(eval $$(call COPY_PKG,iproute2,$(1)))

build-iproute2-$(1): $$(BUILD_DIR_$(1))/iproute2/.built

$$(BUILD_DIR_$(1))/iproute2/.built: $$(BUILD_DIR_$(1))/iproute2/.copied
	@echo "=== Building iproute2 for $(1) ==="
	# PKG_CONFIG=false: every optional library (libelf, libmnl, libcap,
	# libbpf, SELinux ...) is found through pkg-config; without it the build
	# uses none of the host's, natively and cross
	cd "$$(BUILD_DIR_$(1))/iproute2" && \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar PKG_CONFIG=false \
	  ./configure --prefix=/usr
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)" \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/iproute2"
	@touch "$$@"
	@echo "=== iproute2 built ($(1)) ==="

install-iproute2-$(1): build-iproute2-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/iproute2" DESTDIR="$$(ROOTFS_$(1))" install
endef

# ── dhcpcd (custom configure) ─────────────────────────────────────────────

define DHCPCD_BUILD_RULES
$$(eval $$(call COPY_PKG,dhcpcd,$(1)))

build-dhcpcd-$(1): $$(BUILD_DIR_$(1))/dhcpcd/.built

$$(BUILD_DIR_$(1))/dhcpcd/.built: $$(BUILD_DIR_$(1))/dhcpcd/.copied
	@echo "=== Building dhcpcd for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/dhcpcd" && \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)" \
	  ./configure --prefix=/usr --sysconfdir=/etc --datadir=/usr/share \
	    --libexecdir=/usr/libexec --dbdir=/var/db/dhcpcd --rundir=/var/run/dhcpcd \
	    --without-openssl
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/dhcpcd"
	@touch "$$@"
	@echo "=== dhcpcd built ($(1)) ==="

install-dhcpcd-$(1): build-dhcpcd-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/dhcpcd" DESTDIR="$$(ROOTFS_$(1))" install
endef

# ── vim (custom configure) ────────────────────────────────────────────────

define VIM_BUILD_RULES
$$(eval $$(call COPY_PKG,vim,$(1)))

build-vim-$(1): $$(BUILD_DIR_$(1))/vim/.built

$$(BUILD_DIR_$(1))/vim/.built: $$(BUILD_DIR_$(1))/vim/.copied
	@echo "=== Building vim for $(1) ==="
	# Terminal library: the staged ncurses (NCURSES_* in 00-vars.mk).
	# vim's configure keeps a cache (src/auto/config.cache) and refuses to run
	# when CPPFLAGS/LDFLAGS differ from the last run: start without it, so a
	# rebuild in an existing build directory works after a flag change
	rm -f "$$(BUILD_DIR_$(1))/vim/src/auto/config.cache"
	cd "$$(BUILD_DIR_$(1))/vim/src" && ./configure \
		--prefix=/usr --with-features=tiny --disable-gui \
		--without-x --disable-netbeans --disable-channel \
		--disable-gpm --disable-acl --disable-nls \
		--disable-darwin --disable-smack --disable-selinux \
		--disable-xsmp --disable-xsmp-interact \
		--enable-gui=no --without-luajit \
		--with-compiledby="linux-vm" \
		--host=$$(TRIPLET_$(1)) \
		--with-tlib=ncursesw $$(NCURSES_ENV_$(1)) \
		vim_cv_toupper_broken=no \
		vim_cv_terminfo=yes \
		vim_cv_tty_group=world \
		ac_cv_sizeof_int=4 \
		vim_cv_tgetent=zero \
		vim_cv_terminfo=yes \
		CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS) $$(NCURSES_LDFLAGS_$(1))"
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/vim/src"
	@touch "$$@"
	@echo "=== vim built ($(1)) ==="

# STRIP=true: vim's configure picks the build host's strip, which cannot read
# cross-compiled binaries ("Unable to recognise the format"). strip-all-$(1)
# strips with the right tool later (and honours STRIP=0).
install-vim-$(1): build-vim-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/vim" DESTDIR="$$(ROOTFS_$(1))" STRIP=true install
endef

# ── runit (custom build — package/compile) ────────────────────────────────

define RUNIT_BUILD_RULES
$$(eval $$(call COPY_PKG,runit,$(1)))

build-runit-$(1): $$(BUILD_DIR_$(1))/runit/.built

$$(BUILD_DIR_$(1))/runit/.built: $$(BUILD_DIR_$(1))/runit/.copied
	@echo "=== Building runit for $(1) ==="
	# runit's build system reads conf-cc/conf-ld files, not CC env var
	# Override them with the cross-compiler when cross-compiling
	if [ -n "$(CROSS_$(1))" ]; then \
	  sed -i 's|^gcc|$(CROSS_$(1))gcc|' "$$(BUILD_DIR_$(1))/runit/src/conf-cc"; \
	  sed -i 's|^gcc|$(CROSS_$(1))gcc|' "$$(BUILD_DIR_$(1))/runit/src/conf-ld"; \
	fi
	cd "$$(BUILD_DIR_$(1))/runit" && \
	  package/compile
	@touch "$$@"
	@echo "=== runit built ($(1)) ==="

install-runit-$(1): build-runit-$(1)
	mkdir -p "$$(ROOTFS_$(1))/bin"
	for prog in runit runit-init runsv runsvdir runsvchdir chpst sv svlogd utmpset; do \
		[ -f "$$(BUILD_DIR_$(1))/runit/command/$$$$prog" ] && cp "$$(BUILD_DIR_$(1))/runit/command/$$$$prog" "$$(ROOTFS_$(1))/bin/"; \
	done
endef

# ── OpenSSL (libcrypto only, for OpenSSH) ─────────────────────────────────
# Built from the pinned source, so the image never gets the build host's
# libcrypto. Only libcrypto.so.3 goes into the rootfs; headers and libraries
# are staged in openssl-stage/ for the OpenSSH build. Everything OpenSSH
# does not use is left out.
OPENSSL_CONFIGURE := shared no-apps no-docs no-tests no-legacy no-engine no-module \
    no-quic no-comp no-ct no-ocsp no-cms no-ts no-srp no-rfc3779 \
    no-sm2 no-sm3 no-sm4 no-camellia no-aria no-seed no-idea \
    no-rc2 no-rc4 no-rc5 no-md4 no-mdc2 no-whirlpool no-bf no-cast

define OPENSSL_BUILD_RULES
$$(eval $$(call COPY_PKG,openssl,$(1)))

build-openssl-$(1): $$(BUILD_DIR_$(1))/openssl/.built

$$(BUILD_DIR_$(1))/openssl/.built: $$(BUILD_DIR_$(1))/openssl/.copied
	@echo "=== Building openssl (libcrypto) for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/openssl" && ./Configure $$(OPENSSL_TARGET_$(1)) \
	  $$(if $$(CROSS_$(1)),--cross-compile-prefix=$$(CROSS_$(1))) \
	  --prefix=/usr --libdir=lib --openssldir=/etc/ssl $$(OPENSSL_CONFIGURE) \
	  $$(COMMON_CFLAGS)
	$$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/openssl" build_libs
	rm -rf "$$(BUILD_DIR_$(1))/openssl-stage"
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/openssl" install_dev DESTDIR="$$(BUILD_DIR_$(1))/openssl-stage"
	@touch "$$@"

install-openssl-$(1): build-openssl-$(1)
	mkdir -p "$$(ROOTFS_$(1))/lib"
	cp -L "$$(BUILD_DIR_$(1))/openssl-stage/usr/lib/libcrypto.so.3" "$$(ROOTFS_$(1))/lib/"
endef

# ── OpenSSH (ssh, sshd, scp, sftp, ssh-keygen ...) ────────────────────────
# Against the staged OpenSSL; no PAM, zlib, Kerberos, FIDO, PKCS#11 or
# login records. No libcrypt either (the build host's): crypt() serves only
# password logins, which sshd_config disables; with ac_cv_*crypt=no OpenSSH
# falls back to OpenSSL's DES_crypt for the remaining code path. Host keys are not generated here: the sshd service creates
# them on first boot (every VM gets its own). Installed programs that a VM
# does not need are removed in install-openssh.
OPENSSH_CONFIGURE := --prefix=/usr --sysconfdir=/etc/ssh --libexecdir=/usr/libexec \
    --with-privsep-path=/var/empty --with-privsep-user=sshd --with-pid-dir=/run \
    --with-default-path=/usr/local/bin:/usr/bin:/bin \
    --with-superuser-path=/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin \
    --without-pam --without-zlib --without-selinux --without-kerberos5 \
    --without-libedit --without-audit --without-security-key-builtin --without-rpath \
    --disable-security-key --disable-pkcs11 --disable-strip \
    --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
    ac_cv_lib_crypt_crypt=no ac_cv_func_crypt=no

define OPENSSH_BUILD_RULES
$$(eval $$(call COPY_PKG,openssh,$(1)))

build-openssh-$(1): $$(BUILD_DIR_$(1))/openssh/.built

$$(BUILD_DIR_$(1))/openssh/.built: $$(BUILD_DIR_$(1))/openssh/.copied $$(BUILD_DIR_$(1))/openssl/.built
	@echo "=== Building openssh for $(1) ==="
	cd "$$(BUILD_DIR_$(1))/openssh" && autoreconf -fi
	# LD_LIBRARY_PATH: configure runs test programs (native builds), which must
	# load the staged libcrypto, not the build host's (a different OpenSSL
	# fails the header/library version check). Only for configure: the
	# binaries get no rpath, the image has this libcrypto in /lib.
	cd "$$(BUILD_DIR_$(1))/openssh" && \
	  LD_LIBRARY_PATH="$$(BUILD_DIR_$(1))/openssl-stage/usr/lib" ./configure $$(call HOST_FLAG,$(1)) \
	  $$(OPENSSH_CONFIGURE) --with-ssl-dir="$$(BUILD_DIR_$(1))/openssl-stage/usr" \
	  CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)"
	$$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/openssh"
	@touch "$$@"

install-openssh-$(1): build-openssh-$(1) install-openssl-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/openssh" DESTDIR="$$(ROOTFS_$(1))" install-nokeys
	cd "$$(ROOTFS_$(1))" && rm -f usr/bin/ssh-keyscan usr/libexec/ssh-keysign \
	  usr/libexec/ssh-pkcs11-helper usr/libexec/ssh-sk-helper
	mkdir -p "$$(ROOTFS_$(1))/var/empty"
	chmod 755 "$$(ROOTFS_$(1))/var/empty"
endef

# ── ncurses (libncursesw for bash, vim, procps-ng, util-linux) ────────────
# Built from the pinned source so that no package links the build host's
# ncurses/tinfo, native and cross alike. Only libncursesw.so.6 goes into
# the rootfs; headers, libraries and ncursesw.pc are staged in
# ncurses-stage/ for the packages that use it (NCURSES_* in 00-vars.mk).
# Terminal descriptions for the usual terminals are compiled into the
# library (fallbacks); a terminfo directory is still read if present.
# The fallbacks are C code generated by tic + infocmp for this version's
# structures, so those two are first built for the build machine from the
# same source (build-host/), not taken from the host.
NCURSES_FALLBACKS := vt100,vt102,vt220,linux,ansi,dumb,xterm,xterm-256color,screen,screen-256color,tmux,tmux-256color,alacritty
NCURSES_COMMON    := --without-debug --without-ada --without-cxx --without-cxx-binding \
    --without-manpages --without-tests --disable-db-install
NCURSES_CONFIGURE := --prefix=/usr --libdir=/usr/lib --with-shared --without-normal \
    $(NCURSES_COMMON) --without-progs --enable-overwrite --disable-stripping \
    --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig \
    --with-terminfo-dirs=/etc/terminfo:/usr/share/terminfo \
    --with-fallbacks=$(NCURSES_FALLBACKS)

define NCURSES_BUILD_RULES
$$(eval $$(call COPY_PKG,ncurses,$(1)))

build-ncurses-$(1): $$(BUILD_DIR_$(1))/ncurses/.built

$$(BUILD_DIR_$(1))/ncurses/.built: $$(BUILD_DIR_$(1))/ncurses/.copied
	@echo "=== Building ncurses for $(1) ==="
	rm -rf "$$(BUILD_DIR_$(1))/ncurses/build-host" "$$(BUILD_DIR_$(1))/ncurses/build-target" "$$(NCURSES_STAGE_$(1))"
	mkdir -p "$$(BUILD_DIR_$(1))/ncurses/build-host" "$$(BUILD_DIR_$(1))/ncurses/build-target"
	cd "$$(BUILD_DIR_$(1))/ncurses/build-host" && ../configure --without-shared --with-normal $$(NCURSES_COMMON) CC=gcc
	$$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/ncurses/build-host/include"
	$$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/ncurses/build-host/ncurses"
	$$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/ncurses/build-host/progs" tic infocmp
	cd "$$(BUILD_DIR_$(1))/ncurses/build-target" && ../configure $$(call HOST_FLAG,$(1)) $$(NCURSES_CONFIGURE) \
	  --with-build-cc=gcc --with-tic-path="$$(BUILD_DIR_$(1))/ncurses/build-host/progs/tic" \
	  --with-infocmp-path="$$(BUILD_DIR_$(1))/ncurses/build-host/progs/infocmp" \
	  CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS)"
	$$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/ncurses/build-target"
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/ncurses/build-target" install.libs install.includes DESTDIR="$$(NCURSES_STAGE_$(1))"
	# tinfow.pc: the terminfo functions are in libncursesw (no separate
	# libtinfow). util-linux requires this description (its static-build
	# check runs even with --disable-static) and otherwise falls back to
	# the build host's -ltinfo
	printf '%s\n' 'prefix=/usr' 'libdir=$$$${prefix}/lib' 'includedir=$$$${prefix}/include' '' \
	  'Name: tinfow' 'Description: terminfo functions (in libncursesw)' 'Version: 6.6' \
	  'Libs: -L$$$${libdir} -lncursesw' 'Cflags: -I$$$${includedir}' \
	  > "$$(NCURSES_STAGE_$(1))/usr/lib/pkgconfig/tinfow.pc"
	@touch "$$@"

install-ncurses-$(1): build-ncurses-$(1)
	mkdir -p "$$(ROOTFS_$(1))/usr/lib"
	cp -a "$$(NCURSES_STAGE_$(1))"/usr/lib/libncursesw.so.6* "$$(ROOTFS_$(1))/usr/lib/"
endef
