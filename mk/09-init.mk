# ═════════════════════════════════════════════════════════════════════════════
# Phase 4 — Init system (/etc skeleton + runit service directories)
# ═════════════════════════════════════════════════════════════════════════════

TEMPLATES_DIR := $(CURDIR)/templates

define INSTALL_INIT
install-init-$(1):
	@echo "=== Installing init system + /etc skeleton ($(1)) ==="
	TTY=ttyS0; \
	if [ "$(1)" = "arm64" ]; then TTY=ttyAMA0; fi; \
	ROOT="$(ROOTFS_$(1))"; \
	TEMPLATES="$(TEMPLATES_DIR)"; \
	for f in fstab passwd group shadow hostname hosts resolv.conf; do \
	  cp "$${TEMPLATES}/etc/$${f}" "$${ROOT}/etc/$${f}"; \
	done; \
	chmod 644 "$${ROOT}/etc/passwd" "$${ROOT}/etc/group"; \
	chmod 600 "$${ROOT}/etc/shadow"; \
	mkdir -p "$${ROOT}/etc/runit"; \
	cp "$${TEMPLATES}/etc/runit/1" "$${TEMPLATES}/etc/runit/2" \
	   "$${TEMPLATES}/etc/runit/3" "$${TEMPLATES}/etc/runit/ctrlaltdel" \
	   "$${ROOT}/etc/runit/"; \
	chmod 755 "$${ROOT}/etc/runit/1" "$${ROOT}/etc/runit/2" \
	         "$${ROOT}/etc/runit/3" "$${ROOT}/etc/runit/ctrlaltdel"; \
	GETTYDIR="$${ROOT}/etc/service/getty-$${TTY}"; \
	mkdir -p "$${GETTYDIR}/log/main"; \
	sed "s/TTY/$${TTY}/g" "$${TEMPLATES}/etc/service/getty-TTY/run" > "$${GETTYDIR}/run"; \
	sed "s/TTY/$${TTY}/g" "$${TEMPLATES}/etc/service/getty-TTY/finish" > "$${GETTYDIR}/finish"; \
	cp "$${TEMPLATES}/etc/service/getty-TTY/log/run" "$${GETTYDIR}/log/run"; \
	chmod 755 "$${GETTYDIR}/run" "$${GETTYDIR}/finish" "$${GETTYDIR}/log/run"; \
	mkdir -p "$${ROOT}/etc/init.d" \
	         "$${ROOT}/root" "$${ROOT}/home" "$${ROOT}/tmp" \
	         "$${ROOT}/proc" "$${ROOT}/sys" "$${ROOT}/dev" "$${ROOT}/run" \
	         "$${ROOT}/var/log" "$${ROOT}/var/run" "$${ROOT}/var/db" \
	         "$${ROOT}/var/spool" "$${ROOT}/var/tmp" "$${ROOT}/var/lock"
	@echo "=== Init system installed ($(1)) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_INIT,$(t))))
