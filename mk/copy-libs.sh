#!/bin/sh
# Copy every shared library the rootfs needs (DT_NEEDED, recursively) into
# <rootfs>/lib, taking it from the given search directories (host or cross
# sysroot). Fails if a needed library cannot be found anywhere.
#
# Usage: copy-libs.sh <rootfs> <readelf> <search-dir>...
#
# Native builds link against whatever the host has (e.g. ncurses, gmp, pam on
# a Void Linux build VM), so a fixed library list is not enough.

set -eu

rootfs=$1 readelf=$2
shift 2
"$readelf" --version >/dev/null 2>&1 || { echo "ERROR: $readelf not usable" >&2; exit 1; }

# Library directories inside the rootfs that the dynamic loader searches,
# plus any library file anywhere in the rootfs: private library directories
# (glibc's gconv modules need libJIS.so etc. from /usr/lib/gconv, perl and
# gcc keep their own) are found by RUNPATH/$ORIGIN or dlopen, not by the
# default search path
in_rootfs() {
	for d in lib lib64 usr/lib usr/lib64; do
		[ -e "$rootfs/$d/$1" ] && return 0
	done
	printf '%s\n' "$present" | grep -qxF -- "$1"
}

find_lib() {
	for d in "$@"; do
		[ -e "$d/$lib" ] && { echo "$d/$lib"; return 0; }
	done
	return 1
}

mkdir -p "$rootfs/lib"
missing=
while :; do
	copied=0
	present=$(find "$rootfs" \( -type f -o -type l \) -name '*.so*' | sed 's|.*/||' | sort -u)
	for lib in $(find "$rootfs" -type f \( -perm -u+x -o -name '*.so*' \) \
			-exec "$readelf" -d {} + 2>/dev/null |
		sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u); do
		in_rootfs "$lib" && continue
		if src=$(find_lib "$@"); then
			cp -L "$src" "$rootfs/lib/$lib"
			echo "  $lib  <- $src"
			copied=1
		else
			case " $missing " in *" $lib "*) ;; *) missing="$missing $lib" ;; esac
		fi
	done
	[ $copied = 1 ] || break
done

if [ -n "$missing" ]; then
	echo "ERROR: needed libraries not found in: $*" >&2
	echo "ERROR: missing:$missing" >&2
	exit 1
fi
