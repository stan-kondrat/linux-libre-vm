#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Check the dev image from inside a container (as the current user).
#
# Usage: scripts/container-test.sh [TAG]
#   TAG  the release tag the image must say it is (default: only check that
#        the identity files exist)
#
# Checks the release identity files, then compiles, links and (native only)
# runs hello world with gcc and with every /opt/cross/*/bin/*-gcc. Run it as
# root and as uid 1000 (build-release.yml does both).
# ═════════════════════════════════════════════════════════════════════════════

set -eu

TAG=${1:-}
D=/usr/share/linux-libre-vm
fail=0
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

echo "user: $(id -u):$(id -g), kernel: $(uname -sr)"

for f in release commit "MANIFEST-dev-$(uname -m | sed 's/aarch64/arm64/').txt"; do
	[ -s "$D/$f" ] || { echo "FAIL: $D/$f missing"; fail=1; }
done
rel=$(cat "$D/release" 2>/dev/null || true)
echo "release: $rel, commit: $(cat "$D/commit" 2>/dev/null || true)"
if [ -n "$TAG" ] && [ "$rel" != "$TAG" ]; then echo "FAIL: release is '$rel', expected '$TAG'"; fail=1; fi
grep -q "^VERSION_ID=\"$rel\"" /etc/os-release || { echo "FAIL: /etc/os-release does not say $rel"; fail=1; }

cat > "$t/hello.c" <<'C'
#include <stdio.h>
int main(void) { puts("hello"); return 0; }
C

gcc -o "$t/hello" "$t/hello.c"
[ "$("$t/hello")" = hello ] && echo "ok   gcc" || { echo "FAIL: gcc hello"; fail=1; }

n=0
for c in /opt/cross/*/bin/*-gcc; do
	[ -x "$c" ] || continue
	n=$((n + 1))
	if "$c" -o "$t/x" "$t/hello.c"; then echo "ok   $c"; else echo "FAIL: $c"; fail=1; fi
done
[ "$n" -eq 7 ] || { echo "FAIL: $n cross compilers, expected 7"; fail=1; }

exit "$fail"
