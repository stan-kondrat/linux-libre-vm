#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Make a dev disk image say which release it is published as.
#
# A tag publishes the build of the `main` run of its commit; that build was
# made before the tag existed, so its identity files say "edge". This writes
# the tag into the image (release, /etc/os-release; the commit stays) and
# compresses it again, so the .img.xz of a release and its container agree.
# An image that already says TAG is passed through unchanged.
#
# Usage: scripts/retag-image.sh ARCH TAG IN_DIR OUT_DIR
#   IN_DIR   has linux-libre-vm-dev-ARCH.img.xz (or its .partNN pieces)
#   OUT_DIR  receives the same files, and img.sha256 (sha256 of each)
#
# Needs sudo (loop mount), xz and about 9 GB of free disk. Linux only.
# ═════════════════════════════════════════════════════════════════════════════

set -eu

A=$1
TAG=$2
IN=$3
OUT=$4
HERE=$(cd "$(dirname "$0")" && pwd)
base=linux-libre-vm-dev-$A.img.xz
work=${RUNNER_TEMP:-$(mktemp -d)}
img=$work/retag-$A.img
mnt=$work/retag-$A.mnt

mkdir -p "$OUT" "$mnt"

if [ -f "$IN/$base" ]; then xz -dc "$IN/$base" > "$img"
elif ls "$IN/$base".part* >/dev/null 2>&1; then cat "$IN/$base".part* | xz -dc > "$img"
else echo "retag-image: no $base in $IN" >&2; exit 2
fi

sudo mount -o loop "$img" "$mnt"
trap 'sudo umount "$mnt" 2>/dev/null || true; rm -f "$img"' EXIT

D=$mnt/usr/share/linux-libre-vm
have=$(cat "$D/release" 2>/dev/null || true)
commit=$(cat "$D/commit" 2>/dev/null || echo "${GITHUB_SHA:-unknown}")

if [ "$have" = "$TAG" ]; then
	echo "$A: the image already says $TAG; files unchanged"
	cp "$IN/$base"* "$OUT/"
else
	echo "$A: the image says '${have:-nothing}': writing release $TAG ($commit)"
	sudo mkdir -p "$D"
	printf '%s\n' "$TAG" | sudo tee "$D/release" >/dev/null
	printf '%s\n' "$commit" | sudo tee "$D/commit" >/dev/null
	"$HERE/os-release.sh" "$TAG" "$commit" | sudo tee "$mnt/etc/os-release" >/dev/null
	sudo chmod 644 "$D/release" "$D/commit" "$mnt/etc/os-release"
	sudo umount "$mnt"
	trap 'rm -f "$img"' EXIT
	xz -T0 -6 -c "$img" > "$OUT/$base"
	# Release assets are limited to 2 GiB: split like build-dev.yml does
	if [ "$(stat -c %s "$OUT/$base")" -gt 2000000000 ]; then
		split -b 1900M -d "$OUT/$base" "$OUT/$base.part" && rm "$OUT/$base"
	fi
fi

(cd "$OUT" && sha256sum "$base"* > img.sha256)
cat "$OUT/img.sha256"
