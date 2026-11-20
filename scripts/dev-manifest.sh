#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Print MANIFEST-dev-<arch>.txt: what the dev image was built from.
#
# Usage: scripts/dev-manifest.sh ARCH ROOTFS      (run in the repository)
# Environment: TOOLCHAIN_WORK (cross toolchains' BUILD-INFO), COMMIT (default:
#   git HEAD); ImageOS, ImageVersion of the runner when set.
# ═════════════════════════════════════════════════════════════════════════════

set -eu

A=$1
ROOTFS=$2
W=${TOOLCHAIN_WORK:?TOOLCHAIN_WORK not set}
COMMIT=${COMMIT:-$(git rev-parse HEAD)}

echo "linux-libre-vm dev image $A"
echo "commit:  $COMMIT ($(git describe --tags --always 2>/dev/null || echo '?'))"
echo "built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "runner:  ${ImageOS:-?} ${ImageVersion:-?} ($(uname -m)), host gcc $(gcc -dumpfullversion)"
echo; echo "## Toolchain sources (submodule commits)"
git ls-tree HEAD sources/toolchain/ sources/linux-libre | awk '{ print $3, $4 }'
echo; echo "## Cross toolchains"
for f in "$W"/cross/*/*/BUILD-INFO; do echo; cat "$f"; done
echo; echo "## Sizes"
du -sh "$ROOTFS" "$W"/cross/*/*-linux-* 2>/dev/null || true
