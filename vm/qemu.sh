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
# With VM_DIR set, the instance state (pid, log) lives in VM_DIR and the
# folder VM_DIR/shared is shared with the guest over 9p (mount tag "share");
# VM_DIR/vm.sh runs this script for that VM (./vm.sh help).
#
# Usage: vm/qemu.sh <command> [args]
#   run                    boot in the foreground, console on this terminal
#                          (quit: Ctrl-a x)
#   start                  boot in the background (console on a pty)
#   console [--force]      interactive serial console (Ctrl-] quits); only one
#                          at a time, --force takes it over from another one
#   exec [--force] [CMD ...]  log in as root on the serial console, run CMDs
#   serial-path            host pseudo-TTY of the serial console
#   status                 started / stopped
#   help | version         this help / tool, git and QEMU versions
#   stop                   power off (kills QEMU after 10 s)
#   create | recreate | delete
#                          check settings (and download a release) / stop and
#                          reset (fresh disk copy, newest release) / stop and
#                          remove state; never the shared folder
#
# Environment:
#   ARCH     arm64 | x86_64             (default: arm64)
#   VM_DIR   directory for state and shared folder, e.g. vm_tmp/linux-libre-default
#            (default: build/qemu/NAME, no shared folder)
#   NAME     instance name              (default: basename of VM_DIR, else
#                                        linux-libre-ARCH)
#   SHARE    host folder shared with the guest (default: VM_DIR/shared;
#            empty = no sharing)
#   VM_SOURCE  where the kernel and disk come from when KERNEL is not set:
#            release — download a GitHub release (vm/release.sh), the default;
#                      the VM gets its own copy of the disk (VM state dir)
#            local   — this repo's build output, disk used in place
#   VM_RELEASE release tag for VM_SOURCE=release (default: latest; the tag
#            found first is kept for the VM until 'recreate')
#   KERNEL   kernel image (overrides VM_SOURCE)
#   INITRD   initrd (optional)
#   DISK     raw disk image, attached as /dev/vda and written to directly
#            unless SNAPSHOT=1 (default: from VM_SOURCE when KERNEL is not set)
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
if [ -n "${VM_DIR:-}" ]; then
	mkdir -p "$VM_DIR"
	VM_DIR=$(cd "$VM_DIR" && pwd)
	NAME=${NAME:-$(basename "$VM_DIR")}
	SHARE=${SHARE-$VM_DIR/shared}  # unset: default; set but empty: no sharing
fi
NAME=${NAME:-linux-libre-$ARCH}
SHARE=${SHARE:-}
MEM=${MEM:-256}
CPUS=${CPUS:-1}
NET=${NET:-user}
ACCEL=${ACCEL:-auto}
SNAPSHOT=${SNAPSHOT:-0}
TIMEOUT=${TIMEOUT:-60}
VM_SOURCE=${VM_SOURCE:-release}
VM_RELEASE=${VM_RELEASE:-latest}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
STATE=${VM_DIR:-$(cd "$HERE/.." && pwd)/build/qemu/$NAME}
PIDFILE=$STATE/qemu.pid
LOG=$STATE/qemu.log
TAGFILE=$STATE/release  # tag of the release this VM was created from
KERNEL_SET=${KERNEL:-} DISK_SET=${DISK:-}  # chosen by the caller (stored in vm.sh)

die() { echo "qemu.sh: $*" >&2; exit 1; }

case $ARCH in
arm64)
	QEMU=qemu-system-aarch64
	TTY=ttyAMA0
	BLK=virtio-blk-device NIC=virtio-net-device NINEP=virtio-9p-device
	;;
x86_64)
	QEMU=qemu-system-x86_64
	TTY=ttyS0
	BLK=virtio-blk-pci NIC=virtio-net-pci NINEP=virtio-9p-pci
	;;
*) die "ARCH must be arm64 or x86_64 (got '$ARCH')" ;;
esac
APPEND_SET=${APPEND:-}  # only an explicit APPEND is stored in vm.sh
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
	if [ -n "$SHARE" ]; then
		# security_model=none: guest writes land as the host user; works on
		# host folders without xattr support (e.g. a UTM/virtiofs mount)
		echo -fsdev; echo "local,id=share0,path=$SHARE,security_model=none"
		echo -device; echo "$NINEP,fsdev=share0,mount_tag=share"
	fi
	if [ "$NET" = user ]; then
		echo -netdev; echo user,id=net0
		echo -device; echo "$NIC,netdev=net0"
	fi
	for x in ${QEMU_EXTRA:-}; do echo "$x"; done
}

# Kernel and disk: an explicit KERNEL wins, otherwise VM_SOURCE picks a
# downloaded release or the local build output
resolve_files() {
	[ -z "${KERNEL:-}" ] || return 0
	case $VM_SOURCE in
	release)
		tag=$VM_RELEASE
		[ "$tag" != latest ] || [ ! -f "$TAGFILE" ] || tag=$(cat "$TAGFILE")
		out=$(VM_RELEASE=$tag "$HERE/release.sh" fetch "$ARCH") || exit 1
		KERNEL=$(echo "$out" | sed -n 's/^KERNEL=//p')
		if [ -z "${DISK:-}" ]; then
			# QEMU writes to the disk: give the VM its own copy, keep the
			# downloaded image pristine
			DISK=$STATE/disk-$ARCH.img
			mkdir -p "$STATE"
			if [ ! -f "$DISK" ]; then
				cp "$(echo "$out" | sed -n 's/^DISK=//p')" "$DISK.part" && mv "$DISK.part" "$DISK"
			fi
		fi
		basename "$(dirname "$KERNEL")" >"$TAGFILE"
		;;
	local)
		case $ARCH in
		arm64) KERNEL=$REPO/sources-build/arm64/linux-libre/arch/arm64/boot/Image.gz ;;
		x86_64) KERNEL=$REPO/sources-build/x86_64/linux-libre/arch/x86/boot/bzImage ;;
		esac
		DISK=${DISK:-$REPO/disks/disk-$ARCH.img}
		[ -f "$KERNEL" ] && [ -f "$DISK" ] || die "no local build ($KERNEL, $DISK):" \
			"run 'make build install disk-image', or use VM_SOURCE=release"
		;;
	*) die "VM_SOURCE must be release or local (got '$VM_SOURCE')" ;;
	esac
}

check() {
	command -v "$QEMU" >/dev/null || die "$QEMU not found (install QEMU)"
	resolve_files
	[ -f "$KERNEL" ] || die "kernel not found: $KERNEL"
	[ -z "${INITRD:-}" ] || [ -f "$INITRD" ] || die "initrd not found: $INITRD"
	[ -z "${DISK:-}" ] || [ -f "$DISK" ] || die "disk not found: $DISK"
	case ${DISK:-} in *,*) die "DISK path must not contain ',': $DISK" ;; esac
	if [ -n "$SHARE" ]; then
		mkdir -p "$SHARE"
		SHARE=$(cd "$SHARE" && pwd)
		case $SHARE in *,*) die "SHARE path must not contain ',': $SHARE" ;; esac
	fi
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

# VM_DIR/vm.sh: per-VM management script (see vm/write-vm-sh.sh)
write_vm_sh() {
	[ -n "${VM_DIR:-}" ] || return 0
	if [ -n "$KERNEL_SET" ]; then
		set -- KERNEL="$KERNEL_SET" VM_SOURCE= VM_RELEASE=
	else
		set -- KERNEL= VM_SOURCE="$VM_SOURCE" VM_RELEASE="$VM_RELEASE"
	fi
	env "$@" ARCH="$ARCH" INITRD="${INITRD:-}" DISK="$DISK_SET" VM_DIR="$VM_DIR" \
		APPEND="${APPEND_SET:-}" MEM="$MEM" CPUS="$CPUS" "$HERE/write-vm-sh.sh"
}

# Forget the disk copy and the pinned release (recreate / delete)
reset_state() { rm -f "$STATE/disk-$ARCH.img" "$TAGFILE"; }

cmd_start() {
	check
	write_vm_sh
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
	running || die "'$NAME' is not running; start it first"
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
             exec python3 "$HERE/serial-exec.py" "$tty" --interactive --name "$NAME" "$@" ;;
exec)        tty=$(cmd_serial_path) || exit 1
             exec python3 "$HERE/serial-exec.py" "$tty" --name "$NAME" \
               --login root --timeout "$TIMEOUT" "$@" ;;
serial-path) cmd_serial_path ;;
status)      running && echo started || echo stopped ;;
stop)        cmd_stop ;;
create)      check; write_vm_sh; echo "ok: $NAME ($QEMU, accel $(accel)), kernel $KERNEL" ;;
recreate)    cmd_stop >/dev/null; reset_state; check; write_vm_sh
             echo "reset $NAME, kernel $KERNEL, disk $DISK" ;;
delete)      cmd_stop >/dev/null; reset_state; rm -f "$PIDFILE" "$LOG"
             [ -n "${VM_DIR:-}" ] || rm -rf "$STATE"  # VM_DIR keeps shared/
             echo "deleted $NAME" ;;
args)        check; qemu_args ;;  # debugging: print the QEMU command line
help | -h | --help)
             awk 'NR > 2 && /^# ═/ { exit } NR > 2' "$0" | sed 's/^# \{0,1\}//' ;;
version | --version)
             echo "vm/qemu.sh $(cat "$HERE/VERSION") (linux-libre-vm $(git -C "$HERE/.." rev-parse --short HEAD 2>/dev/null || echo unknown))"
             if command -v "$QEMU" >/dev/null; then "$QEMU" --version | head -1; else echo "$QEMU not found"; fi ;;
*)           awk 'NR > 2 && /^# ═/ { exit } NR > 2' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
