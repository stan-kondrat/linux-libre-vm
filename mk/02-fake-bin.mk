# ═════════════════════════════════════════════════════════════════════════════
# Fake-bin setup (stubs for tools missing on build host)
# ═════════════════════════════════════════════════════════════════════════════

FAKE_AUTOPOINT  := $(FAKE_BIN)/autopoint
FAKE_GPERF      := $(FAKE_BIN)/gperf
FAKE_HELP2MAN   := $(FAKE_BIN)/help2man
FAKE_GTKDOCIZE  := $(FAKE_BIN)/gtkdocize
FAKE_RSYNC      := $(FAKE_BIN)/rsync

$(FAKE_BIN)/.stamp: $(FAKE_AUTOPOINT) $(FAKE_GPERF) $(FAKE_HELP2MAN) $(FAKE_GTKDOCIZE) $(FAKE_RSYNC)
	@touch "$@"


$(FAKE_AUTOPOINT):
	@mkdir -p "$(FAKE_BIN)"
	@printf '#!/bin/sh\necho "autopoint (GNU gettext-tools) 0.22.5"\nexit 0\n' > "$@"
	@chmod +x "$@"

$(FAKE_GPERF):
	@mkdir -p "$(FAKE_BIN)"
	@printf '%s\n' \
	  '#!/bin/sh' \
	  'if [ "$$1" = "--version" ]; then echo "GNU gperf 3.1"; exit 0; fi' \
	  'input=""' \
	  'for arg; do case "$$arg" in -*) ;; *) input="$$arg";; esac; done' \
	  '[ -z "$$input" ] && input="/dev/stdin"' \
	  '{ printf "/* gperf stub */\n#include <string.h>\n#include <stddef.h>\n";' \
	  '  awk '"'"'!/^#|^$$|^%|^\/\*/ && /^[a-zA-Z_]/ { print "static int never_use_" $$1 "(void) { return 1; }" }'"'"' "$$input"; }' > "$@"
	@chmod +x "$@"

$(FAKE_HELP2MAN):
	@mkdir -p "$(FAKE_BIN)"
	@printf '#!/bin/sh\necho "help2man (GNU) 1.49"\nexit 0\n' > "$@"
	@chmod +x "$@"

$(FAKE_GTKDOCIZE):
	@mkdir -p "$(FAKE_BIN)"
	@printf '#!/bin/sh\necho "gtkdocize (GNU gtk-doc) 1.34.0"\ncat >gtk-doc.make <<"EOF"\n# Stub gtk-doc.make\nEXTRA_DIST =\nCLEANFILES =\nall:\ninstall:\nclean:\n.PHONY: all install clean\nEOF\nexit 0\n' > "$@"
	@chmod +x "$@"

$(FAKE_RSYNC):
	@mkdir -p "$(FAKE_BIN)"
	@printf '#!/bin/sh\n' > "$@"
	@printf '# Fake rsync — copies with cp -a\n' >> "$@"
	@printf 'src=; dst=\n' >> "$@"
	@printf 'for arg; do\n' >> "$@"
	@printf '  case "$$arg" in -*) continue ;; esac\n' >> "$@"
	@printf '  if [ -z "$$src" ]; then src="$$arg"; else dst="$$arg"; fi\n' >> "$@"
	@printf 'done\n' >> "$@"
	@printf 'if [ -d "$$src" ]; then\n' >> "$@"
	@printf '  base="$$(basename "$$src")"\n' >> "$@"
	@printf '  mkdir -p "$$dst/$$base"\n' >> "$@"
	@printf '  cp -a "$$src"/. "$$dst/$$base"/\n' >> "$@"
	@printf 'else\n' >> "$@"
	@printf '  cp -a "$$src" "$$dst"\n' >> "$@"
	@printf 'fi\n' >> "$@"
	@chmod +x "$@"
