#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Import a dev rootfs tarball as a container image (no Dockerfile): the image
# is exactly the rootfs of the disk image, as one layer.
#
# Usage: scripts/container-import.sh ROOTFS_TAR ARCH TAG
#   ROOTFS_TAR  uncompressed tar of the rootfs (tar -C rootfs-dev --numeric-owner -c .)
#   ARCH        arm64 | x86_64
#   TAG         release tag or "edge"; the image is IMAGE:TAG-ARCH
#
# Environment:
#   IMAGE          default ghcr.io/stan-kondrat/linux-libre-vm-dev
#   REVISION       commit (default: the rootfs's own /usr/share/linux-libre-vm/commit)
#   IMG_SHA        sha256 of the matching linux-libre-vm-dev-ARCH.img.xz (label)
#   MANIFEST_FILE  MANIFEST-dev-ARCH.txt to add (an image built before the
#                  release identity files existed, see backfill-container.yml)
#
# When the rootfs does not say TAG (a tag that published the build of an
# earlier "edge" run, or an image without identity files), release, commit and
# /etc/os-release are replaced inside the tarball first; the rest is the
# rootfs as built. Needs GNU tar. Does not push.
# ═════════════════════════════════════════════════════════════════════════════

set -eu

TAR=$1
ARCH=$2
TAG=$3
IMAGE=${IMAGE:-ghcr.io/stan-kondrat/linux-libre-vm-dev}
REPO=${GITHUB_REPOSITORY:-stan-kondrat/linux-libre-vm}
D=usr/share/linux-libre-vm
HERE=$(cd "$(dirname "$0")" && pwd)

[ -f "$TAR" ] || { echo "container-import: $TAR not found" >&2; exit 2; }

have=$(tar -xOf "$TAR" "./$D/release" 2>/dev/null || true)
REVISION=${REVISION:-$(tar -xOf "$TAR" "./$D/commit" 2>/dev/null || true)}
[ -n "$REVISION" ] || { echo "container-import: no commit (set REVISION)" >&2; exit 2; }

if [ "$have" != "$TAG" ] || [ -n "${MANIFEST_FILE:-}" ]; then
	echo "rootfs says '${have:-nothing}': writing release $TAG into it"
	ov=$(mktemp -d)
	trap 'rm -rf "$ov"' EXIT
	mkdir -p "$ov/$D" "$ov/etc"
	printf '%s\n' "$TAG" > "$ov/$D/release"
	printf '%s\n' "$REVISION" > "$ov/$D/commit"
	files="./$D/release ./$D/commit ./etc/os-release"
	if [ -n "${MANIFEST_FILE:-}" ]; then
		cp "$MANIFEST_FILE" "$ov/$D/MANIFEST-dev-$ARCH.txt"
		files="$files ./$D/MANIFEST-dev-$ARCH.txt"
	fi
	"$HERE/os-release.sh" "$TAG" "$REVISION" > "$ov/etc/os-release"
	# the old entries go (when there are any), the new ones follow
	for f in $files; do tar --delete -f "$TAR" "$f" 2>/dev/null || true; done
	tar -C "$ov" --numeric-owner --owner=0 --group=0 --mode=u=rw,go=r -rf "$TAR" $files
fi

case $ARCH in
arm64) platform=linux/arm64 ;;
x86_64) platform=linux/amd64 ;;
*) echo "container-import: unknown ARCH $ARCH" >&2; exit 2 ;;
esac

docker import --platform "$platform" \
	--change "LABEL org.opencontainers.image.title=linux-libre-vm-dev" \
	--change "LABEL org.opencontainers.image.description='linux-libre-vm dev image: gcc, glibc, binutils, make, perl, Python, Node.js, cross toolchains in /opt/cross'" \
	--change "LABEL org.opencontainers.image.version=$TAG" \
	--change "LABEL org.opencontainers.image.revision=$REVISION" \
	--change "LABEL org.opencontainers.image.source=https://github.com/$REPO" \
	--change "LABEL io.github.stan-kondrat.linux-libre-vm.img-xz-sha256=${IMG_SHA:-}" \
	--change 'ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
	--change 'CMD ["/bin/sh"]' \
	- "$IMAGE:$TAG-$ARCH" < "$TAR"
echo "imported $IMAGE:$TAG-$ARCH"
