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
			$(USERLAND_CONFIG) \
			CFLAGS="$(COMMON_CFLAGS)" \
			LDFLAGS="$(COMMON_LDFLAGS)" || exit 1
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
	    $$($(1)_CONFIGURE_$(2)) \
	    CFLAGS="$(COMMON_CFLAGS)" LDFLAGS="$(COMMON_LDFLAGS)"
	printf '%s\n' 'all:' 'install:' 'clean:' '.PHONY: all install clean' > "$$(BUILD_DIR_$(2))/$(1)/po/Makefile" 2>/dev/null || true
	# Gawk fix: command.c must use bison -p zz prefix (ylwrap overrides specific rule)
	if [ "$(1)" = "gawk" ] && [ -f "$$(BUILD_DIR_$(2))/$(1)/command.y" ]; then \
	  bison -y -p zz -o "$$(BUILD_DIR_$(2))/$(1)/command.c" "$$(BUILD_DIR_$(2))/$(1)/command.y" 2>/dev/null; \
	  touch "$$(BUILD_DIR_$(2))/$(1)/command.c"; \
	fi
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
	  PATH="$(TC_PATH_$(2)):$(FAKE_BIN_PATH)" GNULIB_SRCDIR="$(GNULIB_DIR)" ./bootstrap --gen 2>&1 || GNULIB_SRCDIR="$(GNULIB_DIR)" ./bootstrap 2>&1 | \
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
	# Gawk fix: command.c must use bison -p zz prefix (ylwrap overrides specific rule)
	if [ "$(1)" = "gawk" ] && [ -f "$$(BUILD_DIR_$(2))/$(1)/command.y" ]; then \
	  bison -y -p zz -o "$$(BUILD_DIR_$(2))/$(1)/command.c" "$$(BUILD_DIR_$(2))/$(1)/command.y" 2>/dev/null; \
	  touch "$$(BUILD_DIR_$(2))/$(1)/command.c"; \
	fi
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

# ═════════════════════════════════════════════════════════════════════════════
# Custom build macros (per-target)
# ═════════════════════════════════════════════════════════════════════════════

# ── tar (gnulib + paxutils) ───────────────────────────────────────────────

define TAR_BUILD_RULES
$$(eval $$(call COPY_PKG,tar,$(1)))

build-tar-$(1): $$(BUILD_DIR_$(1))/tar/.built

$$(BUILD_DIR_$(1))/tar/.built: $$(BUILD_DIR_$(1))/tar/.copied | $(FAKE_BIN)/.stamp
	@echo "=== Building tar for $(1) (gnulib bootstrap, in-tree) ==="
	# Ensure paxutils & gnulib submodules are populated (they may be empty on fresh clone)
	if [ -d "$(SOURCES_DIR)/tar/.git" ] || [ -f "$(SOURCES_DIR)/tar/.git" ]; then \
	  cd "$(SOURCES_DIR)/tar" && git submodule update --init paxutils gnulib 2>/dev/null || true; \
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
	    --prefix=/usr --disable-nls --disable-silent-rules \
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
	cd "$$(BUILD_DIR_$(1))/iproute2" && \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  ./configure --prefix=/usr
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  CFLAGS="-O2 -pipe -fomit-frame-pointer -s" LDFLAGS="-s -Wl,--as-needed,-z,relro,-z,now" \
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
	    --libexecdir=/usr/libexec --dbdir=/var/db/dhcpcd --rundir=/var/run/dhcpcd
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
	# For cross-compilation: create termcap stub if ncurses is unavailable
	if [ -n "$(CROSS_$(1))" ]; then \
	  mkdir -p "$$(BUILD_DIR_$(1))/vim/src/termcap-stub"; \
	  cp "$(SOURCES_PATCHES_DIR)/vim/termcap-stub.c" "$$(BUILD_DIR_$(1))/vim/src/termcap-stub/"; \
	  cd "$$(BUILD_DIR_$(1))/vim/src/termcap-stub" && \
	    $(CROSS_$(1))gcc -c termcap-stub.c -o termcap-stub.o && \
	    $(CROSS_$(1))ar cr libtermcap.a termcap-stub.o; \
	fi
	cd "$$(BUILD_DIR_$(1))/vim/src" && ./configure \
		--prefix=/usr --with-features=tiny --disable-gui \
		--without-x --disable-netbeans --disable-channel \
		--disable-gpm --disable-acl --disable-nls \
		--disable-darwin --disable-smack --disable-selinux \
		--disable-xsmp --disable-xsmp-interact \
		--enable-gui=no --without-luajit \
		--with-compiledby="linux-vm" \
		--host=$$(TRIPLET_$(1)) \
		$$(if $(CROSS_$(1)),--with-tlib=termcap,--with-tlib=ncurses) \
		vim_cv_toupper_broken=no \
		vim_cv_terminfo=yes \
		vim_cv_tty_group=world \
		ac_cv_sizeof_int=4 \
		vim_cv_tgetent=zero \
		vim_cv_terminfo=yes \
		CFLAGS="$$(COMMON_CFLAGS)" LDFLAGS="$$(COMMON_LDFLAGS) $$(if $(CROSS_$(1)),-Ltermcap-stub)"
	PATH="$(TC_PATH_$(1)):$$(FAKE_BIN_PATH)" \
	  CC=$$(CROSS_$(1))gcc AR=$$(CROSS_$(1))ar \
	  $$(MAKE) $$(PARALLEL) -C "$$(BUILD_DIR_$(1))/vim/src"
	@touch "$$@"
	@echo "=== vim built ($(1)) ==="

install-vim-$(1): build-vim-$(1)
	$$(MAKE) -C "$$(BUILD_DIR_$(1))/vim" DESTDIR="$$(ROOTFS_$(1))" install
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
	mkdir -p "$$(ROOTFS_$(1))/sbin"
	for prog in runsv runsvdir runsvchpfd chpst sv; do \
		[ -f "$$(BUILD_DIR_$(1))/runit/command/$$$$prog" ] && cp "$$(BUILD_DIR_$(1))/runit/command/$$$$prog" "$$(ROOTFS_$(1))/sbin/"; \
	done
endef
