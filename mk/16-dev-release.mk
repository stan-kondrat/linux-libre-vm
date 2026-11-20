# ═════════════════════════════════════════════════════════════════════════════
# Dev rootfs release identity
#
#   make install-dev-release RELEASE=v0.4.0   install-dev + the files below
#
# The disk image (disk-image-dev) and the container image are made from the
# same rootfs, so both say which release and commit they are:
#
#   /usr/share/linux-libre-vm/release                 release tag (or "edge")
#   /usr/share/linux-libre-vm/commit                  commit of this repository
#   /usr/share/linux-libre-vm/MANIFEST-dev-<arch>.txt same file as the release asset
#   /etc/os-release
#
# Kept apart from install-dev (mk/14-toolchain.mk): that file is an input of
# the toolchain and cross cache keys, and changing it would rebuild them.
# RELEASE and COMMIT come from the workflow (build-dev.yml).
# ═════════════════════════════════════════════════════════════════════════════

.PHONY: install-dev-release

RELEASE ?= unreleased
COMMIT  ?= $(shell git rev-parse HEAD 2>/dev/null)

install-dev-release: install-dev
	RELEASE="$(RELEASE)" COMMIT="$(COMMIT)" TOOLCHAIN_WORK="$(TOOLCHAIN_WORK)" \
	  $(CURDIR)/scripts/dev-release.sh "$(ROOTFS_DEV)" $(TC_ARCH)
