#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Smoke-test a VM runner with Alpine Linux netboot files (stand-in for our build)
#
#   vm/alpine-test.sh             UTM (vm/utm.sh, macOS)
#   RUNNER=qemu vm/alpine-test.sh plain QEMU (vm/qemu.sh)
#
# Alpine's kernel needs its initramfs (drivers are modules), otherwise the VM
# shape matches ours: direct kernel boot, virtio-mmio disk + net, PL011 serial.
# Downloads ~20 MB into vm/cache/ (pinned version, checked by SHA-256),
# creates the VM, boots it, checks kernel / disk / network over the serial
# console, and deletes the VM (set KEEP=1 to keep it).
# ═════════════════════════════════════════════════════════════════════════════

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
CACHE=$HERE/cache
ALPINE=https://dl-cdn.alpinelinux.org/alpine/v3.24
NETBOOT=$ALPINE/releases/aarch64/netboot-3.24.2

RUNNER=$HERE/${RUNNER:-utm}.sh
[ -x "$RUNNER" ] || { echo "unknown RUNNER: $RUNNER" >&2; exit 2; }
export ARCH=arm64
export NAME=${NAME:-linux-libre-alpine-test}
export KERNEL=$CACHE/vmlinuz-virt
export INITRD=$CACHE/initramfs-virt
export DISK=$CACHE/blank.img
export APPEND="console=ttyAMA0 ip=dhcp alpine_repo=$ALPINE/main modloop=$NETBOOT/modloop-virt"
export TIMEOUT=${TIMEOUT:-240}  # QEMU without KVM (TCG) boots much slower

mkdir -p "$CACHE"
for f in vmlinuz-virt initramfs-virt; do
	[ -f "$CACHE/$f" ] || curl -fsSL -o "$CACHE/$f" "$NETBOOT/$f"
done
# Alpine publishes no per-file checksums for netboot files; pinned here
if command -v sha256sum >/dev/null; then sha256="sha256sum"; else sha256="shasum -a 256"; fi
(cd "$CACHE" && $sha256 -c /dev/stdin) <<'EOF'
e45e1f6083d1ed45db6647b422e32b6ae6dc54de7b8190b7b97744fb293412e3  vmlinuz-virt
ffe65ec5a0c0bf470042ad28f7ce7aa5f842ce8090e4230fb2703a7a34e1bebe  initramfs-virt
EOF
[ -f "$DISK" ] || dd if=/dev/zero of="$DISK" bs=1048576 count=0 seek=64 2>/dev/null  # sparse 64 MB

cleanup() { [ "${KEEP:-0}" = 1 ] || "$RUNNER" delete; }
trap cleanup EXIT

"$RUNNER" recreate
"$RUNNER" start
out=$("$RUNNER" exec 'uname -m' 'cat /proc/cmdline' 'test -b /dev/vda && echo vda-is-block-device' 'ip -4 addr show eth0') || {
	echo "$out"; echo "FAIL: no shell on the serial console"; exit 1; }
echo "$out"

fail=0
check() { if echo "$out" | grep -q "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "kernel booted (aarch64)"      '^aarch64$'
check "kernel command line"          'alpine_repo='
check "disk attached as /dev/vda"    '^vda-is-block-device$'
check "network up (DHCP address)"    'inet [0-9]'
exit $fail
