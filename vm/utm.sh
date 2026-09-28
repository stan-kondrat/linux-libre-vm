#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# UTM runner — create and drive a direct-kernel-boot arm64 VM in UTM
#
# Uses only tools shipped with macOS + UTM: osascript (UTM AppleScript API),
# utmctl (bundled in UTM.app) and python3 (serial console). No
# Homebrew, no standalone QEMU. See docs/utm.md.
#
# The VM uses UTM's QEMU backend with the Hypervisor.framework (hvf), no UEFI,
# no display. Devices are virtio-mmio (virtio-blk-device / virtio-net-device)
# because the linux-libre arm64 kernel is built without PCI.
#
# Usage: vm/utm.sh <command> [args]
#   create | recreate      create the VM from the environment below
#   start | stop | status  control it (utmctl)
#   console                interactive serial console (Ctrl-] quits)
#   exec [CMD ...]         log in as root on the serial console, run CMDs
#   serial-path            host pseudo-TTY of the serial console
#   delete                 stop and delete the VM
#
# Environment:
#   NAME     VM name in UTM             (default: linux-libre-arm64)
#   KERNEL   kernel image (required for create)
#   INITRD   initrd (optional)
#   DISK     raw disk image (optional), copied into the VM, attached as /dev/vda
#   APPEND   kernel command line        (default: root=/dev/vda rw console=ttyAMA0)
#   MEM      RAM in MiB                 (default: 256)
#   CPUS     CPU cores                  (default: 1)
#   NET      UTM network mode: shared|emulated|host|none  (default: shared)
#   TIMEOUT  seconds for 'exec'         (default: 60)
# ═════════════════════════════════════════════════════════════════════════════

set -eu

NAME=${NAME:-linux-libre-arm64}
APPEND=${APPEND:-root=/dev/vda rw console=ttyAMA0}
MEM=${MEM:-256}
CPUS=${CPUS:-1}
NET=${NET:-shared}
TIMEOUT=${TIMEOUT:-60}
UTMCTL=${UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}
HERE=$(cd "$(dirname "$0")" && pwd)

die() { echo "utm-vm: $*" >&2; exit 1; }

# Absolute path of an existing file. UTM splits QEMU argument strings on
# whitespace and QEMU splits options on ',', so neither may appear in paths.
abspath() {
	[ -f "$1" ] || die "file not found: $1"
	p="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
	case $p in
	*[[:space:],]*) die "path must not contain spaces or ',': $p" ;;
	esac
	echo "$p"
}

vm_exists() {
	osascript - "$NAME" <<-'EOF' | grep -qx true
	on run argv
		tell application "UTM" to return exists virtual machine named (item 1 of argv)
	end run
	EOF
}

cmd_create() {
	[ -n "${KERNEL:-}" ] || die "KERNEL is required"
	case $APPEND in *'"'*) die "APPEND must not contain '\"'" ;; esac
	vm_exists && die "VM '$NAME' already exists (use 'delete' or 'recreate')"
	kernel=$(abspath "$KERNEL")
	initrd=; [ -z "${INITRD:-}" ] || initrd=$(abspath "$INITRD")
	disk=;   [ -z "${DISK:-}" ]   || disk=$(abspath "$DISK")

	osascript - "$NAME" "$kernel" "$initrd" "$disk" "$APPEND" "$MEM" "$CPUS" "$NET" <<-'EOF'
	on run argv
		set {vmName, kernelPath, initrdPath, diskPath, cmdline, memMB, cpuN, netMode} to argv
		-- Resolve file references outside the tell block (inside, UTM would handle them)
		set kernelFile to POSIX file kernelPath
		if initrdPath is not "" then set initrdFile to POSIX file initrdPath
		if diskPath is not "" then set diskFile to POSIX file diskPath
		tell application "UTM"
			-- 'make' rejects a full configuration (-1700), so create a minimal
			-- VM and then edit the configuration UTM filled with defaults
			set vm to make new virtual machine with properties ¬
				{backend:qemu, configuration:{name:vmName, architecture:"aarch64"}}
			set cfg to configuration of vm
			set machine of cfg to "virt"
			set memory of cfg to (memMB as integer)
			set cpu cores of cfg to (cpuN as integer)
			set hypervisor of cfg to true
			set uefi of cfg to false
			set directory share mode of cfg to none
			set displays of cfg to {}

			-- Drives replace the default USB CD + VirtIO (PCI) disk. All use
			-- interface "none" (no guest device from UTM); «constant QeDiQdIN»
			-- because the bare word is ambiguous with directory share mode.
			--  * DISK is imported (copied into the .utm bundle as qcow2), so
			--    UTM owns write access; we attach an mmio device to it below.
			--  * KERNEL/INITRD are removable drives: UTM keeps a sandbox
			--    bookmark to the original file, which lets QEMU read it for
			--    -kernel/-initrd. (A 'file urls' argument does not grant access.)
			set drvs to {}
			if diskPath is not "" then set drvs to drvs & {{interface:«constant QeDiQdIN», source:diskFile}}
			set drvs to drvs & {{interface:«constant QeDiQdIN», removable:true, source:kernelFile}}
			if initrdPath is not "" then set drvs to drvs & {{interface:«constant QeDiQdIN», removable:true, source:initrdFile}}
			set drives of cfg to drvs

			set nics to network interfaces of cfg
			if netMode is "none" then
				set network interfaces of cfg to {}
			else
				set nic to item 1 of nics
				set hardware of nic to "virtio-net-device" -- mmio, kernel has no PCI
				if netMode is "emulated" then
					set mode of nic to emulated
				else if netMode is "host" then
					set mode of nic to host
				else
					set mode of nic to shared
				end if
				set network interfaces of cfg to {nic}
			end if
			update configuration of vm with cfg

			-- UTM splits each argument string on whitespace: quote -append.
			-- UTM names drives "drive<ID>" on the QEMU command line.
			set qargs to {{argument string:"-kernel"}, {argument string:kernelPath}, ¬
				{argument string:"-append"}, {argument string:quote & cmdline & quote}}
			if initrdPath is not "" then
				set qargs to qargs & {{argument string:"-initrd"}, {argument string:initrdPath}}
			end if
			set cfg to configuration of vm
			if diskPath is not "" then
				set driveId to id of item 1 of (drives of cfg)
				set qargs to qargs & {{argument string:"-device"}, ¬
					{argument string:"virtio-blk-device,drive=drive" & driveId}}
			end if
			set qemu additional arguments of cfg to qargs
			update configuration of vm with cfg
		end tell
		return "created " & vmName
	end run
	EOF
}

# Host pseudo-TTY of the first serial port (VM must be running)
cmd_serial_path() {
	osascript - "$NAME" <<-'EOF'
	on run argv
		tell application "UTM" to return address of serial port 1 of virtual machine named (item 1 of argv)
	end run
	EOF
}

cmd_delete() {
	vm_exists || { echo "VM '$NAME' does not exist"; return 0; }
	"$UTMCTL" stop "$NAME" --kill >/dev/null 2>&1 || true
	"$UTMCTL" delete "$NAME"
	echo "deleted $NAME"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
create)      cmd_create ;;
recreate)    cmd_delete; cmd_create ;;
start)       "$UTMCTL" start --hide "$NAME" ;;
console)     # 'utmctl attach' only prints the pty path in UTM 5.0.x
             tty=$(cmd_serial_path)
             [ -e "$tty" ] || die "no serial console (is the VM running?)"
             exec python3 "$HERE/serial-exec.py" "$tty" --interactive ;;
exec)        tty=$(cmd_serial_path) || exit 1
             exec python3 "$HERE/serial-exec.py" "$tty" \
               --login root --timeout "$TIMEOUT" "$@" ;;
serial-path) cmd_serial_path ;;
status)      "$UTMCTL" status "$NAME" ;;
stop)        "$UTMCTL" stop "$NAME" ;;
delete)      cmd_delete ;;
*)           sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
