#!/bin/sh
# Raw ext4 disk image (no partition table; the kernel mounts root=/dev/vda)
# from a root filesystem directory, without root privileges.
#
# Usage: mkimage.sh <rootfs> <image> <size MB>
#
#   - mke2fs -d copies the directory into the new filesystem in one pass;
#   - every file is then owned by root (debugfs): the rootfs was staged by
#     the build user, and sshd refuses keys under a /root it does not own;
#   - file times, filesystem times, UUID and directory hash seed are fixed
#     (SOURCE_DATE_EPOCH, a UUID derived from the image name), so the same
#     rootfs gives the same image metadata on every build;
#   - e2fsck checks the result; any error fails the build.
#
# The image is sparse: only the used blocks take space on disk.

set -eu

rootfs=$1 image=$2 size_mb=$3
epoch=${SOURCE_DATE_EPOCH:-0}
[ -d "$rootfs" ] || { echo "mkimage.sh: $rootfs: no such directory" >&2; exit 1; }

# UUID from the image name: stable across builds, different per image
uuid=$(printf %s "$(basename "$image")" | sha256sum |
	sed 's/^\(.\{8\}\)\(.\{4\}\).\(.\{3\}\).\(.\{3\}\)\(.\{12\}\).*/\1-\2-4\3-8\4-\5/')

find "$rootfs" -exec touch -h -d "@$epoch" {} +

mkdir -p "$(dirname "$image")"
rm -f "$image"
truncate -s "${size_mb}M" "$image"
# Features: no metadata_csum/orphan_file (older e2fsck and kernels), no
# flex_bg/huge_file/dir_nlink (not needed for a small root filesystem)
E2FSPROGS_FAKE_TIME=$epoch mke2fs -F -q -t ext4 -b 4096 \
	-O ^metadata_csum,^orphan_file,^flex_bg,^huge_file,^dir_nlink \
	-U "$uuid" -E "hash_seed=$uuid,root_owner=0:0" \
	-d "$rootfs" "$image"

script=$image.debugfs
(cd "$rootfs" && find . -mindepth 1) | sed 's|^\.||' |
	awk '{ printf "sif \"%s\" uid 0\nsif \"%s\" gid 0\n", $0, $0 }' >"$script"
E2FSPROGS_FAKE_TIME=$epoch debugfs -w -f "$script" "$image" >/dev/null 2>"$script.err"
if grep -v '^debugfs ' "$script.err" | grep -q .; then
	echo "mkimage.sh: debugfs failed:" >&2
	head -20 "$script.err" >&2
	exit 1
fi
rm -f "$script" "$script.err"

e2fsck -fn "$image" >/dev/null
echo "=== $image: $(du -h "$image" | cut -f1) used of ${size_mb} MB ==="
