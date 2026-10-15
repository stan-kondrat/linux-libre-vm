#!/bin/sh
# Make every file in an ext4 image (made with mke2fs -d) owned by root.
#
# mke2fs -d copies the owner of each file in the rootfs, i.e. the build user;
# sshd refuses root's authorized_keys under a /root it does not own
# (StrictModes). debugfs changes the inodes in place, no root needed.
#
# Usage: chown-root.sh <rootfs dir> <image>

set -eu

rootfs=$1 image=$2
script=$image.debugfs
(cd "$rootfs" && find . -mindepth 1) | sed 's|^\.||' |
	awk '{ printf "sif \"%s\" uid 0\nsif \"%s\" gid 0\n", $0, $0 }' >"$script"
printf 'sif / uid 0\nsif / gid 0\n' >>"$script"
debugfs -w -f "$script" "$image" >/dev/null 2>"$script.err"
# debugfs prints its version banner on stderr; anything else is an error
if grep -v '^debugfs ' "$script.err" | grep -q .; then
	echo "chown-root.sh: debugfs failed on $image:" >&2
	head -20 "$script.err" >&2
	exit 1
fi
rm -f "$script" "$script.err"
