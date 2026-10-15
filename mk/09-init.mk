# ═════════════════════════════════════════════════════════════════════════════
# Phase 4 — Init system (/etc skeleton + runit service directories)
# ═════════════════════════════════════════════════════════════════════════════

TEMPLATES_DIR := $(CURDIR)/templates

define INSTALL_INIT
install-init-$(1):
	@echo "=== Installing init system + /etc skeleton ($(1)) ==="
	TTY=ttyS0; if [ "$(1)" = "arm64" ]; then TTY=ttyAMA0; fi; \
	R="$(ROOTFS_$(1))"; T="$(TEMPLATES_DIR)"; \
	for f in fstab passwd group shadow hostname hosts resolv.conf ld.so.conf; do \
	  cp "$$$${T}/etc/$$$${f}" "$$$${R}/etc/$$$${f}"; \
	done; \
	chmod 644 "$$$${R}/etc/passwd" "$$$${R}/etc/group"; \
	chmod 600 "$$$${R}/etc/shadow"; \
	ldconfig -r "$$$${R}" 2>/dev/null || true; \
	mkdir -p "$$$${R}/etc/runit"; \
	cp "$$$${T}/etc/runit/1" "$$$${T}/etc/runit/2" \
	   "$$$${T}/etc/runit/3" "$$$${T}/etc/runit/ctrlaltdel" \
	   "$$$${T}/etc/runit/diag.sh" \
	   "$$$${R}/etc/runit/"; \
	chmod 755 "$$$${R}/etc/runit/1" "$$$${R}/etc/runit/2" \
	         "$$$${R}/etc/runit/3" "$$$${R}/etc/runit/ctrlaltdel" \
	         "$$$${R}/etc/runit/diag.sh"; \
	GD="$$$${R}/etc/service/getty-$$$${TTY}"; \
	mkdir -p "$$$${GD}/log/main"; \
	sed "s/TTY/$$$${TTY}/g" "$$$${T}/etc/service/getty-TTY/run" > "$$$${GD}/run"; \
	sed "s/TTY/$$$${TTY}/g" "$$$${T}/etc/service/getty-TTY/finish" > "$$$${GD}/finish"; \
	cp "$$$${T}/etc/service/getty-TTY/log/run" "$$$${GD}/log/run"; \
	chmod 755 "$$$${GD}/run" "$$$${GD}/finish" "$$$${GD}/log/run"; \
	DD="$$$${R}/etc/service/dhcpcd"; \
	mkdir -p "$$$${DD}/log/main"; \
	cp "$$$${T}/etc/service/dhcpcd/run" "$$$${DD}/run"; \
	cp "$$$${T}/etc/service/dhcpcd/log/run" "$$$${DD}/log/run"; \
	chmod 755 "$$$${DD}/run" "$$$${DD}/log/run"; \
	SD="$$$${R}/etc/service/sshd"; \
	mkdir -p "$$$${SD}/log/main" "$$$${R}/etc/ssh"; \
	cp "$$$${T}/etc/service/sshd/run" "$$$${SD}/run"; \
	cp "$$$${T}/etc/service/sshd/log/run" "$$$${SD}/log/run"; \
	chmod 755 "$$$${SD}/run" "$$$${SD}/log/run"; \
	cp "$$$${T}/etc/ssh/sshd_config" "$$$${R}/etc/ssh/sshd_config"; \
	ln -sf /bin/bash "$$$${R}/bin/sh" 2>/dev/null || true; \
	for prog in poweroff reboot halt shutdown console-shell; do \
	  cp "$$$${T}/bin/$$$${prog}" "$$$${R}/bin/$$$${prog}"; \
	  chmod 755 "$$$${R}/bin/$$$${prog}"; \
	done; \
	mkdir -p "$$$${R}/etc/init.d" \
	         "$$$${R}/root" "$$$${R}/home" "$$$${R}/tmp" \
	         "$$$${R}/proc" "$$$${R}/sys" "$$$${R}/dev" "$$$${R}/run" \
	         "$$$${R}/var/log" "$$$${R}/var/run" "$$$${R}/var/db" \
	         "$$$${R}/var/spool" "$$$${R}/var/tmp" "$$$${R}/var/lock" "$$$${R}/var/empty"; \
	chmod 700 "$$$${R}/root"; \
	chmod 755 "$$$${R}/var/empty"
	@echo "=== Init system installed ($(1)) ==="
endef

$(foreach t,$(TARGETS),$(eval $(call INSTALL_INIT,$(t))))
