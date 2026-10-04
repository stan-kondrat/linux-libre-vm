#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# UTM runner — create and drive a direct-kernel-boot arm64 VM in UTM
#
# Uses only tools shipped with macOS + UTM: osascript (UTM AppleScript API),
# utmctl (bundled in UTM.app) and python3 (serial console). No
# Homebrew, no standalone QEMU. See docs/utm.md.
#
# The VM uses UTM's QEMU backend with the Hypervisor.framework (hvf), no UEFI,
# no display. Devices are virtio-mmio (virtio-blk-device / virtio-net-device /
# virtio-9p-device) because the linux-libre arm64 kernel is built without PCI.
#
# With VM_DIR set, everything lives in that directory instead of UTM's own
# storage: the VM bundle VM_DIR/NAME.utm (config + disk copy) and the shared
# folder VM_DIR/shared, which the guest mounts with 9p (mount tag "share"),
# plus VM_DIR/vm.sh, which runs this script for that VM (./vm.sh help).
#
# Usage: vm/utm.sh <command> [args]
#   create | recreate      create the VM from the environment below
#   start | stop | status  control it (utmctl)
#   console [--force]      interactive serial console (Ctrl-] quits); only one
#                          at a time, --force takes it over from another one
#   exec [--force] [CMD ...]  log in as root on the serial console, run CMDs
#   serial-path            host pseudo-TTY of the serial console
#   delete                 stop and delete the VM (keeps VM_DIR/shared)
#   help | version         this help / tool, git and UTM versions
#   list                   all UTM VMs: name, status, bundle path (bundles
#                          under LIST_DIRS are matched by UUID; others are in
#                          UTM's own storage), plus unregistered bundles
#
# Environment:
#   VM_DIR   directory for the VM bundle and shared folder, e.g. vm_tmp/linux-libre-default
#            (default: none — UTM's own storage, no shared folder)
#   NAME     VM name in UTM             (default: basename of VM_DIR, else
#                                        linux-libre-arm64)
#   SHARE    host folder shared with the guest (default: VM_DIR/shared;
#            empty = no sharing)
#   VM_SOURCE  where 'create' gets the kernel and disk when KERNEL is not set:
#            release — download a GitHub release (vm/release.sh), the default
#            local   — this repo's build output (make build install disk-image)
#   VM_RELEASE release tag for VM_SOURCE=release (default: latest)
#   KERNEL   kernel image (overrides VM_SOURCE)
#   INITRD   initrd (optional)
#   DISK     raw disk image, copied into the VM, attached as /dev/vda
#            (default: from VM_SOURCE when KERNEL is not set)
#   APPEND   kernel command line        (default: root=/dev/vda rw console=ttyAMA0)
#   MEM      RAM in MiB                 (default: 256)
#   CPUS     CPU cores                  (default: 1)
#   NET      UTM network mode: shared|emulated|host|none  (default: shared)
#   TIMEOUT  seconds for 'exec'         (default: 60)
#   LIST_DIRS  directories whose */*.utm bundles 'list' matches
#            (default: <repo>/vm_tmp and the parent of VM_DIR)
# ═════════════════════════════════════════════════════════════════════════════

set -eu

BUNDLE=
if [ -n "${VM_DIR:-}" ]; then
	mkdir -p "$VM_DIR"
	VM_DIR=$(cd "$VM_DIR" && pwd)
	NAME=${NAME:-$(basename "$VM_DIR")}
	BUNDLE=$VM_DIR/$NAME.utm
	SHARE_GIVEN=${SHARE+x}         # set explicitly: recorded in vm.sh
	SHARE=${SHARE-$VM_DIR/shared}  # unset: default; set but empty: no sharing
fi
SHARE=${SHARE:-}
NAME=${NAME:-linux-libre-arm64}
APPEND=${APPEND:-root=/dev/vda rw console=ttyAMA0}
MEM=${MEM:-256}
CPUS=${CPUS:-1}
NET=${NET:-shared}
TIMEOUT=${TIMEOUT:-60}
VM_SOURCE=${VM_SOURCE:-release}
VM_RELEASE=${VM_RELEASE:-latest}
UTMCTL=${UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

die() { echo "utm.sh: $*" >&2; exit 1; }

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

# Kernel and disk for 'create': an explicit KERNEL wins, otherwise VM_SOURCE
# picks a downloaded release or the local build output
resolve_files() {
	[ -z "${KERNEL:-}" ] || return 0
	case $VM_SOURCE in
	release)
		out=$(VM_RELEASE=$VM_RELEASE "$HERE/release.sh" fetch arm64) || exit 1
		KERNEL=$(echo "$out" | sed -n 's/^KERNEL=//p')
		DISK=${DISK:-$(echo "$out" | sed -n 's/^DISK=//p')}
		;;
	local)
		KERNEL=$REPO/sources-build/arm64/linux-libre/arch/arm64/boot/Image.gz
		DISK=${DISK:-$REPO/disks/disk-arm64.img}
		[ -f "$KERNEL" ] && [ -f "$DISK" ] || die "no local build ($KERNEL, $DISK):" \
			"build on Linux with 'make build install disk-image', or use VM_SOURCE=release"
		;;
	*) die "VM_SOURCE must be release or local (got '$VM_SOURCE')" ;;
	esac
}

cmd_create() {
	# vm.sh stores what the caller chose: explicit files, else VM_SOURCE
	# (so 'recreate' of a release VM picks up the newest release)
	kernel_set=${KERNEL:-} disk_set=${DISK:-}
	resolve_files
	case $APPEND in *'"'*) die "APPEND must not contain '\"'" ;; esac
	vm_exists && die "VM '$NAME' already exists (use 'delete' or 'recreate')"
	kernel=$(abspath "$KERNEL")
	initrd=; [ -z "${INITRD:-}" ] || initrd=$(abspath "$INITRD")
	disk=;   [ -z "${DISK:-}" ]   || disk=$(abspath "$DISK")
	share=
	if [ -n "$SHARE" ]; then
		mkdir -p "$SHARE"
		share=$(cd "$SHARE" && pwd)
		case $share in *[[:space:],]*) die "SHARE path must not contain spaces or ',': $share" ;; esac
	fi
	[ -z "$BUNDLE" ] || [ ! -e "$BUNDLE" ] || die "$BUNDLE already exists (use 'delete' or 'recreate')"

	osascript - "$NAME" "$kernel" "$initrd" "$disk" "$APPEND" "$MEM" "$CPUS" "$NET" "$share" <<-'EOF' >/dev/null
	on run argv
		set {vmName, kernelPath, initrdPath, diskPath, cmdline, memMB, cpuN, netMode, sharePath} to argv
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
			-- VirtFS: UTM adds "-fsdev local,id=virtfs0,path=<shared dir>" (the
			-- dir itself is set per registration, see cmd_share) plus a PCI
			-- virtio-9p device. That gives QEMU sandbox access to the folder,
			-- but UTM's fsdev uses security_model=mapped-xattr, which makes
			-- symlinks created on the Mac unreadable in the guest ("Too many
			-- levels of symbolic links") and keeps guest-side modes apart from
			-- the real ones. We add our own fsdev on the same folder with
			-- security_model=none (host files as they are) and an mmio device
			if sharePath is "" then
				set directory share mode of cfg to none
			else
				set directory share mode of cfg to VirtFS
			end if
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
			if sharePath is not "" then
				set qargs to qargs & {{argument string:"-fsdev"}, ¬
					{argument string:"local,id=share1,path=" & sharePath & ",security_model=none"}, ¬
					{argument string:"-device"}, ¬
					{argument string:"virtio-9p-device,fsdev=share1,mount_tag=share"}}
			end if
			set qemu additional arguments of cfg to qargs
			update configuration of vm with cfg
		end tell
		return "created " & vmName
	end run
	EOF

	if [ -n "$BUNDLE" ]; then
		# Move the VM out of UTM's storage: export the bundle to VM_DIR,
		# delete UTM's copy, and open the exported bundle, which UTM then
		# registers in place (a linked VM, running from VM_DIR)
		osascript - "$NAME" "$BUNDLE" <<-'EOF'
		on run argv
			set dst to POSIX file (item 2 of argv)
			tell application "UTM" to export virtual machine named (item 1 of argv) to dst
		end run
		EOF
		"$UTMCTL" delete "$NAME"
		open -g -a UTM "$BUNDLE"
		i=0
		until vm_exists; do
			i=$((i + 1)); [ $i -le 30 ] || die "UTM did not register $BUNDLE"
			sleep 1
		done
	fi
	[ -z "$share" ] || cmd_share "$share"
	if [ -n "$BUNDLE" ]; then
		# Record an explicitly chosen shared folder (empty = none) for recreate
		if [ -n "${SHARE_GIVEN:-}" ]; then export SHARE_SAVE=${share:-none}; fi
		if [ -n "$kernel_set" ]; then
			ARCH=arm64 KERNEL=$kernel INITRD=$initrd DISK=$disk VM_DIR=$VM_DIR "$HERE/write-vm-sh.sh"
		else
			ARCH=arm64 KERNEL= INITRD=$initrd DISK=$disk_set VM_SOURCE=$VM_SOURCE \
				VM_RELEASE=$VM_RELEASE VM_DIR=$VM_DIR "$HERE/write-vm-sh.sh"
		fi
	fi
	case $kernel_set:$VM_SOURCE in
	:release) from="release $(basename "$(dirname "$kernel")")" ;;
	:local) from="local build" ;;
	*) from=$kernel ;;
	esac
	echo "created $NAME from $from${BUNDLE:+ in $VM_DIR}${share:+, shared folder $share}"
	[ -z "$BUNDLE" ] || echo "manage it with $VM_DIR/vm.sh (help, start, console, ...)"
}

# Set the VM's shared directory. UTM keeps it in the registration, not the
# config, and 'update registry' is the scripting call that changes it.
cmd_share() {
	osascript - "$NAME" "$1" <<-'EOF' >/dev/null
	on run argv
		set dir to POSIX file (item 2 of argv)
		tell application "UTM" to update registry of virtual machine named (item 1 of argv) with {dir}
	end run
	EOF
}

vm_status() { "$UTMCTL" status "$NAME" 2>/dev/null || echo "not found"; }

# utmctl prints "Error from event: ... (OSStatus error -10004.)" on every
# start although it works; the outcome is checked with 'status' instead
utmctl_quiet() {
	{ "$UTMCTL" "$@" 2>&1 >&3 | grep -v 'OSStatus error -10004' >&2; } 3>&1 || true
}

cmd_start() {
	case $(vm_status) in
	started) echo "$NAME is already running"; return 0 ;;
	"not found") die "VM '$NAME' does not exist (use 'create')" ;;
	esac
	utmctl_quiet start --hide "$NAME"
	i=0
	until [ "$(vm_status)" = started ]; do
		i=$((i + 1)); [ $i -le 10 ] || die "$NAME did not start (status: $(vm_status))"
		sleep 1
	done
	echo "started $NAME; attach with: ${VM_DIR:+$VM_DIR/vm.sh }console"
}

cmd_stop() {
	case $(vm_status) in
	stopped) echo "$NAME is not running"; return 0 ;;
	"not found") die "VM '$NAME' does not exist" ;;
	esac
	utmctl_quiet stop "$NAME"
	i=0
	until [ "$(vm_status)" = stopped ]; do
		i=$((i + 1)); [ $i -le 15 ] || die "$NAME did not stop (status: $(vm_status))"
		sleep 1
	done
	echo "stopped $NAME"
}

# Host pseudo-TTY of the first serial port. UTM still reports the last path
# after the VM stopped, so check that it runs.
cmd_serial_path() {
	st=$(vm_status)
	[ "$st" = started ] || die "$NAME is not running (status: $st); start it first"
	osascript - "$NAME" <<-'EOF'
	on run argv
		tell application "UTM" to return address of serial port 1 of virtual machine named (item 1 of argv)
	end run
	EOF
}

# Deleting a VM removes its bundle (also a linked one in VM_DIR) but never the
# shared folder
cmd_delete() {
	if vm_exists; then
		"$UTMCTL" stop "$NAME" --kill >/dev/null 2>&1 || true
		"$UTMCTL" delete "$NAME"
	elif [ -n "$BUNDLE" ] && [ -e "$BUNDLE" ]; then
		rm -rf "$BUNDLE"  # left over, not registered in UTM
	else
		echo "VM '$NAME' does not exist"; return 0
	fi
	echo "deleted $NAME"
}

# UTM's scripting interface has no bundle path, and its registry is inside
# UTM's sandbox container. Bundles we manage are found on disk instead and
# matched to registered VMs by the UUID in their config.plist.
cmd_list() {
	dirs=${LIST_DIRS:-"$(cd "$HERE/.." && pwd)/vm_tmp${VM_DIR:+ $(dirname "$VM_DIR")}"}
	vms=$(osascript <<-'EOF'
	tell application "UTM"
		set out to ""
		repeat with v in virtual machines
			set out to out & (id of v) & tab & (name of v) & tab & ((status of v) as text) & linefeed
		end repeat
	end tell
	return out
	EOF
	)
	bundles=$(for d in $dirs; do
		for b in "$d"/*/*.utm; do
			[ -f "$b/config.plist" ] || continue
			u=$(plutil -extract Information.UUID raw "$b/config.plist" 2>/dev/null) || continue
			printf '%s\t%s\n' "$u" "$b"
		done
	done | sort -u)
	tab=$(printf '\t')
	pretty() { case $1 in "$HOME"/*) echo "~${1#"$HOME"}" ;; *) echo "$1" ;; esac; }
	printf '%-24s %-15s %s\n' NAME STATUS PATH
	echo "$vms" | while IFS=$tab read -r id name status; do
		[ -n "$id" ] || continue
		path=$(echo "$bundles" | awk -F'\t' -v u="$id" '$1 == u { print $2; exit }')
		if [ -n "$path" ]; then path=$(pretty "$path"); else path="(UTM storage)"; fi
		printf '%-24s %-15s %s\n' "$name" "$status" "$path"
	done
	echo "$bundles" | while IFS=$tab read -r id path; do
		[ -n "$id" ] || continue
		echo "$vms" | grep -q "^$id$tab" && continue
		printf '%-24s %-15s %s\n' "$(basename "$path" .utm)" "not registered" "$(pretty "$path")"
	done
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
create)      cmd_create ;;
recreate)    cmd_delete; cmd_create ;;
start)       cmd_start ;;
console)     # 'utmctl attach' only prints the pty path in UTM 5.0.x
             tty=$(cmd_serial_path) || exit 1
             exec python3 "$HERE/serial-exec.py" "$tty" --interactive --name "$NAME" "$@" ;;
exec)        tty=$(cmd_serial_path) || exit 1
             exec python3 "$HERE/serial-exec.py" "$tty" --name "$NAME" \
               --login root --timeout "$TIMEOUT" "$@" ;;
serial-path) cmd_serial_path ;;
status)      "$UTMCTL" status "$NAME" ;;
stop)        cmd_stop ;;
delete)      cmd_delete ;;
list)        cmd_list ;;
help | -h | --help)
             awk 'NR > 2 && /^# ═/ { exit } NR > 2' "$0" | sed 's/^# \{0,1\}//' ;;
version | --version)
             echo "vm/utm.sh $(cat "$HERE/VERSION") (linux-libre-vm $(git -C "$HERE/.." rev-parse --short HEAD 2>/dev/null || echo unknown))"
             echo "UTM $("$UTMCTL" version 2>/dev/null || echo 'not found')" ;;
*)           awk 'NR > 2 && /^# ═/ { exit } NR > 2' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
