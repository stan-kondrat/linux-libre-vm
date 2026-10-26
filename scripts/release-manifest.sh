#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Print a release manifest for one architecture: upstream source versions,
# toolchain, the build host's packages whose libraries were copied into the
# image (their source is the distribution's source package), sizes and the
# file list. Run after `make install-ARCH disk-image-ARCH`.
#
# Usage: scripts/release-manifest.sh ARCH   (x86_64 | arm64)
# ═════════════════════════════════════════════════════════════════════════════

set -eu

ARCH=${1:?usage: release-manifest.sh x86_64|arm64}
cd "$(git rev-parse --show-toplevel)"
ROOT=rootfs/$ARCH
[ -d "$ROOT" ] || { echo "release-manifest.sh: $ROOT not found (run make install-$ARCH)" >&2; exit 1; }
case $ARCH in
arm64) CC=aarch64-linux-gnu-gcc; [ "$(uname -m)" = aarch64 ] && CC=gcc ;;
*) CC=gcc; [ "$(uname -m)" = x86_64 ] || CC=x86_64-linux-gnu-gcc ;;
esac

echo "linux-libre-vm $ARCH"
echo "commit:  $(git rev-parse HEAD) ($(git describe --tags --always 2>/dev/null))"
echo "built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo
echo "## Upstream sources (git submodule status)"
git submodule status | grep -v ' sources/toolchain/' || true

echo
echo "## Toolchain"
$CC --version | head -1

# Libraries in the image that came from the build host (glibc, libgcc,
# ncurses, ...): name the distribution package and version they belong to
if command -v dpkg >/dev/null; then
	echo
	echo "## Host libraries copied into the image (distribution packages)"
	case $ARCH-$(uname -m) in
	arm64-x86_64) want='-arm64-cross' ;;
	x86_64-aarch64) want='-amd64-cross' ;;
	*) want= ;;
	esac
	# A library counts as the host's only if it is the host's file: same ELF
	# build ID (strip keeps it). Libraries built here (libcrypto from
	# sources/openssl, libblkid ... from sources/util-linux) share names with
	# distribution packages but are not theirs.
	build_id() { readelf -n "$1" 2>/dev/null | sed -n 's/.*Build ID: *//p' | head -1; }
	for f in $(cd "$ROOT" && find lib lib64 usr/lib -maxdepth 1 -type f -name '*.so*' 2>/dev/null | sort); do
		b=$(basename "$f")
		id=$(build_id "$ROOT/$f")
		# "*/name": a pattern starting with "/" would be an exact path for dpkg
		dpkg -S "*/$b" 2>/dev/null | sed 's/, /\n/g' | while IFS= read -r line; do
			pkg=${line%%: *} path=${line#*: }
			pkg=${pkg%%:*}
			if [ -n "$want" ]; then
				case $pkg in *"$want") ;; *) continue ;; esac
			else
				case $pkg in *-cross) continue ;; esac
			fi
			[ -f "$path" ] || continue
			if [ -n "$id" ] && [ "$(build_id "$path")" = "$id" ] || cmp -s "$path" "$ROOT/$f"; then
				printf '%-28s %s %s\n' "$b" "$pkg" "$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)"
				break
			fi
		done
	done
fi

echo
echo "## Sizes"
du -sh "$ROOT" | sed 's|\t| |'
for f in disks/disk-$ARCH.img; do [ -f "$f" ] && ls -lh "$f" | awk '{ print $5, $NF }'; done

echo
echo "## Files"
(cd "$ROOT" && find . \( -type f -o -type l \) | sed 's|^\./|/|' | sort)
