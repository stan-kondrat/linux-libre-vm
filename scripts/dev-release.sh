#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Write the release identity files into a dev rootfs (make install-dev-release).
#
# Usage: scripts/dev-release.sh ROOTFS ARCH
# Environment: RELEASE (tag or "edge"), COMMIT, TOOLCHAIN_WORK
# ═════════════════════════════════════════════════════════════════════════════

set -eu

R=$1
A=$2
: "${RELEASE:?}" "${COMMIT:?}"
D=$R/usr/share/linux-libre-vm
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$D" "$R/etc"
printf '%s\n' "$RELEASE" > "$D/release"
printf '%s\n' "$COMMIT" > "$D/commit"
"$HERE/dev-manifest.sh" "$A" "$R" > "$D/MANIFEST-dev-$A.txt"
rm -f "$R/etc/os-release"
"$HERE/os-release.sh" "$RELEASE" "$COMMIT" > "$R/etc/os-release"
chmod 644 "$D"/* "$R/etc/os-release"
echo "release identity: $RELEASE ($COMMIT) in $D"
