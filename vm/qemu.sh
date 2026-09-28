#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# QEMU runner — direct-kernel-boot VM with plain qemu-system-* (see docs/qemu.md)
#
# Same interface as vm/utm.sh, so scripts and tests work with either runner.
# Needs qemu-system-aarch64 / qemu-system-x86_64 and python3 (serial console).
#
# Acceleration is picked automatically: KVM when /dev/kvm is usable and the
# guest matches the host architecture, HVF on macOS (arm64 guest on Apple
# Silicon), otherwise TCG (software emulation: works everywhere, slower).
#
# Devices follow the kernel configs: arm64 uses virtio-mmio on "virt" (the
# kernel has no PCI), x86_64 uses virtio-pci on "q35".
#
# Usage: vm/qemu.sh <command> [args]
#   run                    boot in the foreground, console on this terminal
#                          (quit: Ctrl-a x)
#   start                  boot in the background (console on a pty)
#   console                interactive serial console (Ctrl-] quits)
#   exec [CMD ...]         log in as root on the serial console, run CMDs
#   serial-path            host pseudo-TTY of the serial console
#   status                 started / stopped
#   stop                   power off (kills QEMU after 10 s)
#   create | recreate | delete
#                          check settings / stop and reset / stop and remove
#                          state (for parity with vm/utm.sh)
#
# Environment:
#   ARCH     arm64 | x86_64             (default: arm64)
#   NAME     instance name, state in build/qemu/NAME  (default: linux-libre-ARCH)
#   KERNEL   kernel image (required)
#   INITRD   initrd (optional)
#   DISK     raw disk image (optional), attached as /dev/vda and written to
#            directly unless SNAPSHOT=1
#   APPEND   kernel command line        (default: root=/dev/vda rw console=<serial>)
#   MEM      RAM in MiB                 (default: 256)
#   CPUS     CPU cores                  (default: 1)
#   NET      user | none                (default: user — NAT, guest gets DHCP)
#   ACCEL    auto | kvm | hvf | tcg     (default: auto)
#   SNAPSHOT 1 = discard disk writes on exit (default: 0)
#   TIMEOUT  seconds for 'exec'         (default: 60)
#   QEMU_EXTRA  extra QEMU arguments (word-split)
# ═════════════════════════════════════════════════════════════════════════════

set -eu

ARCH=${ARCH:-arm64}
NAME=${NAME:-linux-libre-$ARCH}
MEM=${MEM:-256}
CPUS=${CPUS:-1}
NET=${NET:-user}
ACCEL=${ACCEL:-auto}
SNAPSHOT=${SNAPSHOT:-0}
TIMEOUT=${TIMEOUT:-60}
HERE=$(cd "$(dirname "$0")" && pwd)
STATE=$(cd "$HERE/.." && pwd)/build/qemu/$NAME
PIDFILE=$STATE/qemu.pid
LOG=$STATE/qemu.log

die() { echo "qemu.sh: $*" >&2; exit 1; }

case $ARCH in
arm64)
	QEMU=qemu-system-aarch64
	TTY=ttyAMA0
	BLK=virtio-blk-device NIC=virtio-net-device
	;;
x86_64)
	QEMU=qemu-system-x86_64
	TTY=ttyS0
	BLK=virtio-blk-pci NIC=virtio-net-pci
	;;
*) die "ARCH must be arm64 or x86_64 (got '$ARCH')" ;;
esac
APPEND=${APPEND:-root=/dev/vda rw console=$TTY}

accel() {
	[ "$ACCEL" = auto ] || { echo "$ACCEL"; return; }
	host=$(uname -m)
	case $host in aarch64 | arm64) host=arm64 ;; esac
	if [ "$host" = "$ARCH" ]; then
		[ -r /dev/kvm ] && [ -w /dev/kvm ] && { echo kvm; return; }
		[ "$(uname -s)" = Darwin ] && { echo hvf; return; }
	fi
	echo tcg
}

# Print the QEMU command line, one argument per line (no quoting issues)
qemu_args() {
	a=$(accel)
	echo "$QEMU"
	echo -name; echo "$NAME"
	echo -m; echo "$MEM"
	echo -smp; echo "$CPUS"
	echo -accel; echo "$a"
	case $ARCH in
	arm64)
		echo -M; echo virt,gic-version=3
		echo -cpu; [ "$a" = tcg ] && echo cortex-a57 || echo host
		;;
	x86_64)
		echo -M; echo q35
		[ "$a" = tcg ] || { echo -cpu; echo host; }
		;;
	esac
	echo -nographic
	echo -nodefaults
	echo -no-reboot
	echo -kernel; echo "$KERNEL"
	[ -z "${INITRD:-}" ] || { echo -initrd; echo "$INITRD"; }
	echo -append; echo "$APPEND"
	if [ -n "${DISK:-}" ]; then
		echo -drive; echo "file=$DISK,format=raw,if=none,id=drive0"
		echo -device; echo "$BLK,drive=drive0"
		[ "$SNAPSHOT" = 1 ] && echo -snapshot
	fi
	if [ "$NET" = user ]; then
		echo -netdev; echo user,id=net0
		echo -device; echo "$NIC,netdev=net0"
	fi
	for x in ${QEMU_EXTRA:-}; do echo "$x"; done
}

check() {
	command -v "$QEMU" >/dev/null || die "$QEMU not found (install QEMU)"
	[ -n "${KERNEL:-}" ] || die "KERNEL is required"
	[ -f "$KERNEL" ] || die "kernel not found: $KERNEL"
	[ -z "${INITRD:-}" ] || [ -f "$INITRD" ] || die "initrd not found: $INITRD"
	[ -z "${DISK:-}" ] || [ -f "$DISK" ] || die "disk not found: $DISK"
	case ${DISK:-} in *,*) die "DISK path must not contain ',': $DISK" ;; esac
	case $NET in user | none) ;; *) die "NET must be user or none" ;; esac
}

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

# Run QEMU with the argument list from qemu_args (newline-separated)
run_qemu() {
	old_ifs=$IFS
	IFS='
'
	# shellcheck disable=SC2046
	set -- $(qemu_args) "$@"
	IFS=$old_ifs
	"$@"
}

cmd_run() {
	check
	running && die "'$NAME' is already running in the background (use stop)"
	echo "qemu.sh: $QEMU, accel $(accel); quit with Ctrl-a x" >&2
	run_qemu -serial mon:stdio
}

cmd_start() {
	check
	running && { echo "'$NAME' is already running"; return 0; }
	mkdir -p "$STATE"
	rm -f "$PIDFILE"
	# The "char device redirected to /dev/pts/N" line goes to stdout or
	# stderr depending on the QEMU version: capture both
	run_qemu -serial pty -monitor none -daemonize -pidfile "$PIDFILE" >"$LOG" 2>&1 ||
		{ cat "$LOG" >&2; die "QEMU failed to start"; }
	tty=$(cmd_serial_path) || { cmd_stop >/dev/null; exit 1; }
	echo "started $NAME ($QEMU, accel $(accel)), console $tty"
}

# QEMU prints "char device redirected to /dev/pts/N (label serial0)" at start
cmd_serial_path() {
	running || die "'$NAME' is not running"
	p=$(sed -n 's/.*char device redirected to \(\/dev\/[^ ]*\).*/\1/p' "$LOG" | head -1)
	[ -n "$p" ] || die "serial pty not found in $LOG"
	echo "$p"
}

cmd_stop() {
	running || { echo "'$NAME' is not running"; return 0; }
	pid=$(cat "$PIDFILE")
	kill "$pid"
	i=0
	while kill -0 "$pid" 2>/dev/null && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done
	kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
	rm -f "$PIDFILE"
	echo "stopped $NAME"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
run)         cmd_run ;;
start)       cmd_start ;;
console)     tty=$(cmd_serial_path) || exit 1
             exec python3 "$HERE/serial-exec.py" "$tty" --interactive ;;
exec)        tty=$(cmd_serial_path) || exit 1
             exec python3 "$HERE/serial-exec.py" "$tty" \
               --login root --timeout "$TIMEOUT" "$@" ;;
serial-path) cmd_serial_path ;;
status)      running && echo started || echo stopped ;;
stop)        cmd_stop ;;
create)      check; echo "ok: $NAME ($QEMU, accel $(accel))" ;;
recreate)    cmd_stop >/dev/null; check; echo "reset $NAME" ;;
delete)      cmd_stop >/dev/null; rm -rf "$STATE"; echo "deleted $NAME" ;;
args)        check; qemu_args ;;  # debugging: print the QEMU command line
*)           sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
