# Running in UTM on macOS (Apple Silicon)

The arm64 build runs as a UTM virtual machine with hardware virtualization
(QEMU backend + Apple Hypervisor.framework). Everything is scripted with
tools that ship with macOS and UTM — no Homebrew, no standalone QEMU:

| Tool | Where it comes from | Used for |
|------|---------------------|----------|
| `osascript` | macOS | UTM AppleScript API: create and configure the VM |
| `utmctl` | `/Applications/UTM.app/Contents/MacOS/utmctl` | start / stop / status / delete / console |
| `python3` | macOS (Xcode Command Line Tools) | scripted serial console (`utm/serial-exec.py`) |

x86_64 images can only be emulated on Apple Silicon (slow); this runner is arm64 only.

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

Requirements: UTM 5.x in `/Applications`. The first run asks
"*Terminal* wants to control *UTM*" (Automation) — allow it.

```bash
make utm-test-alpine   # optional: check the runner works on this Mac
make utm-create        # uses the local build output by default
make utm-start
make utm-console       # serial console; detach with Ctrl-C
make utm-delete
```

With release files instead of a local build:

```bash
make utm-create UTM_KERNEL=linux-libre-vmlinuz-arm64 UTM_DISK=linux-libre-vm-arm64.img
```

The Linux build targets need a Linux host; on macOS only the `utm-*` targets
are usable.

### Script interface

`make utm-*` wraps `utm/utm-vm.sh`, which can also be used directly:

```bash
NAME=my-vm KERNEL=Image.gz DISK=disk-arm64.img utm/utm-vm.sh create
NAME=my-vm utm/utm-vm.sh start
NAME=my-vm utm/utm-vm.sh exec 'uname -a' 'df -h'   # log in as root, run, print
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `NAME` | `linux-libre-arm64` | VM name in UTM |
| `KERNEL` | — | kernel image (required for `create`) |
| `INITRD` | — | optional initrd |
| `DISK` | — | raw disk image, copied into the VM, attached as `/dev/vda` |
| `APPEND` | `root=/dev/vda rw console=ttyAMA0` | kernel command line |
| `MEM` / `CPUS` | `256` / `1` | RAM (MiB) / cores (the kernel is built without SMP) |
| `NET` | `shared` | UTM network mode: `shared`, `emulated`, `host`, `none` |
| `TIMEOUT` | `60` | seconds `exec` waits for boot + commands |

**The disk is a copy.** UTM imports `DISK` into the VM bundle (as qcow2).
After rebuilding the image, run `make utm-recreate` to pick it up; changes
made inside the VM are not written back to `disks/disk-arm64.img`.

## How it works

The VM is created through UTM's AppleScript API with these settings:

- QEMU backend, `aarch64`, machine `virt`, hypervisor on, UEFI off, no display, no directory sharing
- one serial port on a host pseudo-TTY (becomes the guest's PL011 `ttyAMA0`)
- network card `virtio-net-device` in UTM's shared (NAT) mode
- drives with interface "none" (UTM attaches no guest device to them):
  - `DISK`, imported into the bundle
  - `KERNEL` and `INITRD` as **removable** drives, so UTM keeps a sandbox bookmark to the original files
- QEMU additional arguments:
  `-kernel … -append "…" [-initrd …] -device virtio-blk-device,drive=drive<disk-id>`

UTM adds its own devices as well (USB controllers, virtio-serial, virtio-rng on
PCI). The kernel ignores them because it has no PCI support.

### UTM behaviours this relies on

Found while building the runner with UTM 5.0.4:

| Behaviour | Consequence |
|-----------|-------------|
| `make new virtual machine` with a full configuration fails (`-1700 Can't make … into type qemu configuration`) | Create with `{name, architecture}` only, then `update configuration` |
| Each additional-argument string is split on whitespace | The `-append` value is wrapped in `"…"`; paths must not contain spaces |
| `file urls` on an additional argument do **not** let QEMU read that file (`could not load kernel`) | Kernel/initrd are also added as removable drives, which grants read access |
| A file given with `-drive` in additional arguments is not writable (`Operation not permitted`) | The disk is imported as a UTM drive instead |
| The bare word `none` means directory share mode `none` | Drive interface "none" is written as `«constant QeDiQdIN»` |
| Drive IDs appear as `drive<ID>` on the QEMU command line | Our `virtio-blk-device` refers to the imported disk that way |

## Alpine smoke test

`make utm-test-alpine` (`utm/alpine-test.sh`) checks the runner without our
build. It uses Alpine Linux 3.24.2 netboot files for aarch64: `vmlinuz-virt`
and `initramfs-virt`, about 20 MB, downloaded to `utm/cache/` and pinned by
SHA-256. The VM shape matches ours, except that Alpine needs its initramfs to
load drivers. The test:

1. creates the VM with a blank 64 MB disk and boots it
2. logs in as root on the serial console
3. checks that the kernel booted, the command line was passed, `/dev/vda` exists and `eth0` got a DHCP address
4. deletes the VM (keep it with `KEEP=1 make utm-test-alpine`)

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
  attach, so press Enter to get a new login prompt.
- **Serial scripting stalls.** BusyBox's shell asks the terminal for the
  cursor position (`ESC[6n`) and waits for the answer. `serial-exec.py`
  answers it; other tools may need to do the same.
- **"Claude/Terminal wants to access data from other apps".** This prompt
  appears if something tries to read UTM's private container
  (`~/Library/Containers/com.utmapp.UTM`). The runner never needs that, so
  declining is fine.
