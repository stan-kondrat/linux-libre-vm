# ═════════════════════════════════════════════════════════════════════════════
# Phase 4 — Init system (/etc skeleton + runit service directories)
# ═════════════════════════════════════════════════════════════════════════════
#
# templates/etc/service/<name>/ becomes /etc/service/<name>/ (supervised by
# runsvdir). getty-TTY is installed as getty-<console>, with TTY replaced by
# the arch's serial console (TTY_<a> in 00-vars.mk).

TEMPLATES_DIR := $(CURDIR)/templates
ETC_FILES     := fstab passwd group shadow hostname hosts resolv.conf ld.so.conf
RUNIT_FILES   := 1 2 3 ctrlaltdel diag.sh
BIN_SCRIPTS   := poweroff reboot halt shutdown console-shell
SERVICES      := getty-TTY dhcpcd sshd

define INSTALL_INIT
install-init-$(1):
	@echo "=== Installing init system + /etc skeleton ($(1)) ==="
	set -e; R="$(ROOTFS_$(1))"; T="$(TEMPLATES_DIR)"; \
	mkdir -p "$$$$R/etc/runit" "$$$$R/etc/service" "$$$$R/etc/ssh"; \
	for f in $(ETC_FILES); do cp "$$$$T/etc/$$$$f" "$$$$R/etc/$$$$f"; done; \
	chmod 644 "$$$$R/etc/passwd" "$$$$R/etc/group"; \
	chmod 600 "$$$$R/etc/shadow"; \
	cp "$$$$T/etc/ssh/sshd_config" "$$$$R/etc/ssh/sshd_config"; \
	for f in $(RUNIT_FILES); do install -m 755 "$$$$T/etc/runit/$$$$f" "$$$$R/etc/runit/$$$$f"; done; \
	for s in $(SERVICES); do \
	  d="$$$$R/etc/service/$$$$(echo "$$$$s" | sed 's/TTY/$(TTY_$(1))/')"; \
	  rm -rf "$$$$d"; mkdir -p "$$$$d"; \
	  (cd "$$$$T/etc/service/$$$$s" && find . -type f) | while read -r f; do \
	    mkdir -p "$$$$d/$$$$(dirname "$$$$f")"; \
	    sed 's/TTY/$(TTY_$(1))/g' "$$$$T/etc/service/$$$$s/$$$$f" > "$$$$d/$$$$f"; \
	    chmod 755 "$$$$d/$$$$f"; \
	  done; \
	  [ ! -d "$$$$d/log" ] || mkdir -p "$$$$d/log/main"; \
	done; \
	for p in $(BIN_SCRIPTS); do install -m 755 "$$$$T/bin/$$$$p" "$$$$R/bin/$$$$p"; done; \
	ln -sf /bin/bash "$$$$R/bin/sh"; \
	mkdir -p "$$$$R/etc/init.d" "$$$$R/root" "$$$$R/home" "$$$$R/tmp" "$$$$R/proc" "$$$$R/sys" "$$$$R/dev" \
	         "$$$$R/run" "$$$$R/var/log" "$$$$R/var/run" "$$$$R/var/db" "$$$$R/var/spool" \
	         "$$$$R/var/tmp" "$$$$R/var/lock" "$$$$R/var/empty"; \
	chmod 700 "$$$$R/root"; chmod 755 "$$$$R/var/empty"; chmod 1777 "$$$$R/tmp" "$$$$R/var/tmp"; \
	ldconfig -r "$$$$R" 2>/dev/null || true
	@echo "=== Init system installed ($(1)) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_INIT,$(t))))
