# Running in UTM on macOS (Apple Silicon)

The arm64 build runs as a UTM virtual machine with hardware virtualization
(QEMU backend + Apple Hypervisor.framework). Everything is scripted with
tools that ship with macOS and UTM — no Homebrew, no standalone QEMU:

| Tool | Where it comes from | Used for |
|------|---------------------|----------|
| `osascript` | macOS | UTM AppleScript API: create and configure the VM |
| `utmctl` | `/Applications/UTM.app/Contents/MacOS/utmctl` | start / stop / status / delete |
| `python3` | macOS (Xcode Command Line Tools) | serial console, interactive and scripted (`vm/serial-exec.py`) |

x86_64 images can only be emulated on Apple Silicon (slow); this runner is arm64 only.
To run with plain QEMU instead (on Linux, or inside a Linux build VM), see
[qemu.md](qemu.md): same commands, `make qemu-*` instead of `make utm-*`.

## What the build produces

| File | Local build | Release asset |
|------|-------------|---------------|
| Kernel (gzip-compressed arm64 `Image`) | `sources-build/arm64/linux-libre/arch/arm64/boot/Image.gz` | `linux-libre-vmlinuz-arm64` |
| Root filesystem (raw ext4, **no partition table**, 256 MB) | `disks/disk-arm64.img` | `linux-libre-vm-arm64.img` |

No bootloader and no initrd: the kernel is booted directly with
`root=/dev/vda rw console=ttyAMA0`. The arm64 kernel has no PCI support, so
the disk and network must be **virtio-mmio** devices (`virtio-blk-device`,
`virtio-net-device`), and the console is the PL011 UART (`ttyAMA0`).

## Quick start

Requirements: UTM 5.x in `/Applications` (tested with 5.0.4 and 5.0.6). The first run asks
"*Terminal* wants to control *UTM*" (Automation) — allow it.

```bash
make utm-test-alpine   # optional: check the runner works on this Mac
make utm-create        # VM "linux-libre-default" in vm_tmp/linux-libre-default, from the local build output
make utm-start
make utm-console       # serial console; Ctrl-] quits (the VM keeps running)
make utm-list          # all UTM VMs: name, status, bundle path
make utm-delete
```

With release files instead of a local build:

```bash
make utm-create UTM_KERNEL=linux-libre-vmlinuz-arm64 UTM_DISK=linux-libre-vm-arm64.img
```

The Linux build targets need a Linux host; on macOS only the `utm-*` targets
are usable.

### VM directory and shared folder

Everything for a VM lives in one directory, `VM_DIR` (default `vm_tmp/linux-libre-default`,
git-ignored), not in UTM's own storage:

```
vm_tmp/linux-libre-default/
├── linux-libre-default.utm/   UTM bundle: config.plist + Data/<disk>.qcow2 (UTM runs it in place)
├── shared/                    shared with the guest, mounted at /mnt/shared
└── vm.sh                      management script for this VM (generated)
```

`vm.sh` runs `vm/utm.sh` (on macOS) or `vm/qemu.sh` (elsewhere; `RUNNER=utm|qemu`
chooses) with `VM_DIR` set to its directory and the kernel/disk it was created
with, stored relative to the repo. So it works from any directory, and in a
Linux build VM that mounts the repo at another path:

```bash
vm_tmp/linux-libre-default/vm.sh help       # also: version
vm_tmp/linux-libre-default/vm.sh start
vm_tmp/linux-libre-default/vm.sh console
vm_tmp/linux-libre-default/vm.sh recreate   # after rebuilding the disk image
```

The VM is named after the directory. More VMs side by side:
`make utm-create utm-start VM_DIR=vm_tmp/vm2`. `make utm-delete` removes the
bundle but never `shared/`.

Inside the guest the folder is mounted at boot (runit stage 1) when the kernel
has 9p support, which the image's kernel config enables. By hand:

```bash
mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/shared
```

### Script interface

`make utm-*` wraps `vm/utm.sh`, which can also be used directly:

```bash
VM_DIR=vm_tmp/vm2 KERNEL=Image.gz DISK=disk-arm64.img vm/utm.sh create
VM_DIR=vm_tmp/vm2 vm/utm.sh start
VM_DIR=vm_tmp/vm2 vm/utm.sh exec 'uname -a' 'df -h'   # log in as root, run, print
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `VM_DIR` | — (`make`: `vm_tmp/linux-libre-default`) | directory for the bundle and `shared/`; unset = UTM's own storage, no sharing |
| `NAME` | basename of `VM_DIR`, else `linux-libre-arm64` | VM name in UTM |
| `SHARE` | `VM_DIR/shared` | host folder shared with the guest; empty = no sharing |
| `KERNEL` | — | kernel image (required for `create`) |
| `INITRD` | — | optional initrd |
| `DISK` | — | raw disk image, copied into the VM, attached as `/dev/vda` |
| `APPEND` | `root=/dev/vda rw console=ttyAMA0` | kernel command line |
| `MEM` / `CPUS` | `256` / `1` | RAM (MiB) / cores (the kernel is built without SMP) |
| `NET` | `shared` | UTM network mode: `shared`, `emulated`, `host`, `none` |
| `TIMEOUT` | `60` | seconds `exec` waits for boot + commands |

**In the guest**, the serial console opens straight into a root bash (no
password), and the `dhcpcd` runit service configures `eth0` by DHCP from UTM's
shared network at boot.

**The disk is a copy.** UTM imports `DISK` into the VM bundle (as qcow2, in
`VM_DIR/<name>.utm/Data/`).
After rebuilding the image, run `make utm-recreate` to pick it up; changes
made inside the VM are not written back to `disks/disk-arm64.img`.

## How it works

The VM is created through UTM's AppleScript API with these settings:

- QEMU backend, `aarch64`, machine `virt`, hypervisor on, UEFI off, no display
- directory sharing: VirtFS, with the shared folder set through `update registry`
- one serial port on a host pseudo-TTY (becomes the guest's PL011 `ttyAMA0`)
- network card `virtio-net-device` in UTM's shared (NAT) mode
- drives with interface "none" (UTM attaches no guest device to them):
  - `DISK`, imported into the bundle
  - `KERNEL` and `INITRD` as **removable** drives, so UTM keeps a sandbox bookmark to the original files
- QEMU additional arguments:
  `-kernel … -append "…" [-initrd …] -device virtio-blk-device,drive=drive<disk-id>`
  `-device virtio-9p-device,fsdev=virtfs0,mount_tag=share` (mmio 9p on UTM's VirtFS backend)

With `VM_DIR`, the VM is then exported to `VM_DIR/<name>.utm`, UTM's copy is
deleted, and the exported bundle is opened, so UTM registers it in place.

UTM adds its own devices as well (USB controllers, virtio-serial, virtio-rng on
PCI). The kernel ignores them because it has no PCI support.

### UTM behaviours this relies on

Found while building the runner with UTM 5.0.4, still true in 5.0.6:

| Behaviour | Consequence |
|-----------|-------------|
| `make new virtual machine` with a full configuration fails (`-1700 Can't make … into type qemu configuration`) | Create with `{name, architecture}` only, then `update configuration` |
| Each additional-argument string is split on whitespace | The `-append` value is wrapped in `"…"`; paths must not contain spaces |
| `file urls` on an additional argument do **not** let QEMU read that file (`could not load kernel`) | Kernel/initrd are also added as removable drives, which grants read access |
| A file given with `-drive` in additional arguments is not writable (`Operation not permitted`) | The disk is imported as a UTM drive instead |
| The bare word `none` means directory share mode `none` | Drive interface "none" is written as `«constant QeDiQdIN»` |
| Drive IDs appear as `drive<ID>` on the QEMU command line | Our `virtio-blk-device` refers to the imported disk that way |
| `utmctl attach` prints "attach command is not implemented yet!" and the pty path | `utm-console` opens the pty with `vm/serial-exec.py --interactive` instead |
| New VMs always go into UTM's container; `export` writes a bundle anywhere, and opening a `.utm` registers it where it is | `create` exports to `VM_DIR` and reopens it from there |
| Neither the scripting interface nor `utmctl list` report where a VM's bundle is; UTM's registry is inside its sandbox container | `list` finds bundles under `vm_tmp/` (or `LIST_DIRS`) and matches them to VMs by the UUID in `config.plist`; any other VM is shown as "(UTM storage)" |
| `utmctl delete` on a VM registered in place deletes its bundle files too | `delete` never touches `VM_DIR/shared`, which is outside the bundle |
| The QEMU shared folder is not in the configuration but in the registration; `update registry with {folder}` sets it | Set after the VM is registered from `VM_DIR` |
| VirtFS mode adds `-fsdev local,id=virtfs0,…` and a PCI `virtio-9p-pci` device | We add `virtio-9p-device` on the same `virtfs0`, since the kernel has no PCI |

## Alpine smoke test

`make utm-test-alpine` (`vm/alpine-test.sh`) checks the runner without our
build. It uses Alpine Linux 3.24.2 netboot files for aarch64: `vmlinuz-virt`
and `initramfs-virt`, about 20 MB, downloaded to `vm/cache/` and pinned by
SHA-256. The VM shape matches ours, except that Alpine needs its initramfs to
load drivers. The test:

1. creates the VM in `vm_tmp/alpine-test` with a blank 64 MB disk and boots it
2. logs in as root on the serial console
3. checks that the kernel booted, the command line was passed, `/dev/vda` exists and `eth0` got a DHCP address
4. mounts the shared folder and checks that the guest reads a file written on the host, and writes one back
5. deletes the VM and its directory (keep them with `KEEP=1 make utm-test-alpine`)

A full run takes about 50 s. Alpine downloads its packages and kernel modules
at boot, so the Mac needs internet access.

## Troubleshooting

- **Alert "Internal error trying to connect to SPICE server".** QEMU exited
  during startup. UTM always talks to QEMU over SPICE, so this alert is the
  symptom, not the cause. The real error is printed by `utmctl start` /
  `make utm-start` as `QEMU error: …`.
- **See the exact QEMU command line** while the VM runs:
  ```bash
  ps -ww -o command= -p "$(pgrep -f QEMULauncher.app/Contents/MacOS/QEMULauncher)" | sed 's/ -\([a-zA-Z]\)/\n-\1/g'
  ```
- **`make utm-console` shows nothing.** Boot messages go out before you
  attach, and the console sends nothing on attach, so press Enter to get a
  new prompt.
- **"console … is already in use by PID …".** A serial console has a single
  input stream: with two readers attached, each byte goes to only one of
  them, and both show garbled text and seem to freeze. So `console` and
  `exec` take a lock and refuse while another process (another console, a
  running `exec`, `screen`, …) has the port open. Quit the other console
  with Ctrl-] or close its terminal, or pass `--force` to stop it and take
  over: `vm.sh console --force`.
- **`Error from event: … (OSStatus error -10004.)`** is printed by `utmctl`
  on every start although the start works; `vm/utm.sh start` filters it and
  checks the VM's status instead.
- **Serial scripting stalls.** BusyBox's shell asks the terminal for the
  cursor position (`ESC[6n`) and waits for the answer. `serial-exec.py`
  answers it; other tools may need to do the same.
- **"Claude/Terminal wants to access data from other apps".** This prompt
  appears if something tries to read UTM's private container
  (`~/Library/Containers/com.utmapp.UTM`). The runner never needs that, so
  declining is fine.
