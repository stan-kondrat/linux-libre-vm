#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Boot an image under QEMU and check that it works; exits non-zero on any
# failure. Used by `make test` and by CI (both workflows).
#
#   - serial console: kernel is Linux-libre, root filesystem writable,
#     DHCP address on the network
#   - ssh: a throwaway key, added on the serial console (the image has
#     none), then login as root through a forwarded port
#   - PROFILE=dev also: gcc/g++ compile and run, every cross compiler under
#     /opt/cross compiles, make, python3 (zlib, bz2), node
#
# Usage: ARCH=x86_64|arm64 KERNEL=<image> DISK=<image> [PROFILE=base|dev] \
#          scripts/smoke-test.sh
#   SSH_PORT  host port forwarded to the guest's ssh (default: 2222)
#   TIMEOUT   seconds for the serial console steps (default: 300)
#   MEM, CPUS as for vm/qemu.sh (defaults: 512 / 1, dev: 2048 / 2)
# The disk is not modified (SNAPSHOT=1).
# ═════════════════════════════════════════════════════════════════════════════

set -eu

cd "$(dirname "$0")/.."
: "${ARCH:?ARCH required}" "${KERNEL:?KERNEL required}" "${DISK:?DISK required}"
PROFILE=${PROFILE:-base}
case $PROFILE in
base) MEM=${MEM:-512} CPUS=${CPUS:-1} ;;
dev) MEM=${MEM:-2048} CPUS=${CPUS:-2} ;;
*) echo "smoke-test.sh: PROFILE must be base or dev" >&2; exit 2 ;;
esac
SSH_PORT=${SSH_PORT:-2222}
TIMEOUT=${TIMEOUT:-300}
NAME=smoke-$PROFILE-$ARCH
export ARCH KERNEL DISK MEM CPUS SSH_PORT TIMEOUT NAME SNAPSHOT=1 SHARE= VM_DIR=

tmp=$(mktemp -d)
log=$tmp/log
ssh-keygen -q -t rsa -b 3072 -N '' -C smoke-test -f "$tmp/key"
pub=$(cat "$tmp/key.pub")
cleanup() { vm/qemu.sh stop >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

fail=0
check() {  # check <pattern> <what>
	if grep -q -- "$1" "$log"; then echo "ok    $2"; else echo "FAIL  $2"; fail=1; fi
}

vm/qemu.sh start
# dhcpcd may not have its lease yet right after login: wait for it (30 s)
vm/qemu.sh exec 'uname -sr' 'test -w / && echo rootfs-writable' \
	'for i in $(seq 30); do ip -4 -o addr show scope global | grep -q inet && break; sleep 1; done; ip -4 -o addr show scope global' \
	'mkdir -p /root/.ssh && chmod 700 /root/.ssh' \
	"echo '$pub' >/root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && echo key-added" |
	tee "$log"
check '^Linux .*gnu' "kernel is Linux-libre"
check '^rootfs-writable' "root filesystem writable"
check ' inet [0-9]' "DHCP address"
check '^key-added' "ssh key added on the console"

# sshd generates its host keys on the first start: retry for a while
ssh_run() {
	ssh -p "$SSH_PORT" -i "$tmp/key" -o BatchMode=yes -o ConnectTimeout=10 \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		root@127.0.0.1 "$@"
}
i=0
until ssh_run 'echo ssh-ok; echo "processes: $(ps -A --no-headers | wc -l) (user space: $(ps -A --no-headers -o ppid= | grep -vcw 2))"' >"$log" 2>&1; do
	i=$((i + 1))
	[ $i -lt 30 ] || break
	sleep 5
done
cat "$log"
check '^ssh-ok' "ssh login as root"

if [ "$PROFILE" = dev ]; then
	ssh_run sh -s >"$log" 2>&1 <<-'EOF' || true
	. /etc/profile
	cd /tmp
	gcc --version | head -1; make --version | head -1
	echo 'int main(void){return 0;}' >t.c && gcc -o t t.c && ./t && echo smoke-c-ok
	printf '#include <iostream>\nint main(){std::cout<<"smoke-cxx-ok"<<std::endl;}\n' >t.cc &&
		g++ -o tx t.cc && ./tx
	for c in /opt/cross/*/bin/*-gcc; do "$c" -c -o x.o t.c && echo "smoke-cross-ok ${c##*/}"; done
	python3 -c 'import zlib, bz2; print("smoke-py-ok")'
	node -e 'console.log("smoke-node-ok")'
	EOF
	cat "$log"
	check '^smoke-c-ok' "gcc compiles and runs"
	check '^smoke-cxx-ok' "g++ compiles and runs"
	check '^smoke-py-ok' "python3 with zlib, bz2"
	check '^smoke-node-ok' "node"
	n=$(grep -c '^smoke-cross-ok' "$log" || true)
	if [ "$n" -eq 7 ]; then echo "ok    7 cross compilers"; else echo "FAIL  $n of 7 cross compilers"; fail=1; fi
fi

[ $fail = 0 ] && echo "=== smoke test passed ($PROFILE, $ARCH) ===" ||
	{ echo "=== smoke test FAILED ($PROFILE, $ARCH) ==="; exit 1; }
