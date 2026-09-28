# Running with QEMU

`vm/qemu.sh` boots the built kernel and disk image with plain
`qemu-system-*`, on any Linux or macOS host with QEMU installed, including
inside a Linux build VM. It has the same commands as the [UTM runner](utm.md),
so the same workflow and the same Alpine smoke test work with both.

| Need | Install |
|------|---------|
| `qemu-system-aarch64` (arm64 image) | Void: `xbps-install qemu` · Debian/Ubuntu: `apt install qemu-system-arm` |
| `qemu-system-x86_64` (x86_64 image) | Void: `xbps-install qemu` · Debian/Ubuntu: `apt install qemu-system-x86` |
| `python3` | serial console (`console`, `exec`), standard library only |

## What gets booted

Same files as for UTM (see [utm.md](utm.md#what-the-build-produces)): the
kernel is booted directly (no bootloader, no initrd) with the raw ext4 image
as `/dev/vda`.

| | arm64 | x86_64 |
|---|---|---|
| Kernel | `sources-build/arm64/linux-libre/arch/arm64/boot/Image.gz` | `sources-build/x86_64/linux-libre/arch/x86/boot/bzImage` |
| Disk | `disks/disk-arm64.img` | `disks/disk-x86_64.img` |
| Machine | `virt` (GICv3) | `q35` |
| Disk / network devices | `virtio-blk-device` / `virtio-net-device` (mmio — the kernel has no PCI) | `virtio-blk-pci` / `virtio-net-pci` |
| Console | `ttyAMA0` (PL011) | `ttyS0` |

### Acceleration

Picked automatically (`ACCEL=auto`):

| Host | Guest | Accelerator |
|------|-------|-------------|
| Linux, `/dev/kvm` usable | same architecture | `kvm` (`-cpu host`) |
| macOS on Apple Silicon | arm64 | `hvf` (`-cpu host`) |
| anything else | | `tcg` — software emulation, works everywhere but much slower (arm64 uses `-cpu cortex-a57`) |

Inside a UTM VM on a Mac (such as a Void Linux build VM), `/dev/kvm` is
normally not available, so QEMU falls back to TCG. The system still boots,
just more slowly. Override with `ACCEL=kvm|hvf|tcg`.

## Quick start

Foreground, console on this terminal. The VM stops when you quit:

```bash
make qemu-arm64          # quit: Ctrl-a x
make qemu-x86_64
make qemu-arm64 BOOT_DIAG=1   # adds boot.diag=1 (boot diagnostics in runit stage 1)
```

Background, like the UTM runner:

```bash
make qemu-start          # arm64 by default; QEMU_ARCH=x86_64 for the other image
make qemu-console        # serial console; Ctrl-] quits (the VM keeps running)
make qemu-status
make qemu-stop
make qemu-test-alpine    # optional: check the runner works on this host
```

**The disk image is used directly**, so changes made inside the VM are written
to `disks/disk-*.img` (unlike UTM, which works on a copy). Use `SNAPSHOT=1`
with `vm/qemu.sh` to discard them on exit, or rebuild the image with
`make ARCH=arm64 disk-image`.

**Networking** is QEMU user-mode NAT (the guest reaches the network, the host
cannot connect in). The image's `dhcpcd` runit service configures `eth0` by
DHCP at boot (typically `10.0.2.15`); its log is in
`/etc/service/dhcpcd/log/main/current`.

## Script interface

`make qemu-*` wraps `vm/qemu.sh`, which can also be used directly:

```bash
ARCH=arm64 KERNEL=Image.gz DISK=disk-arm64.img vm/qemu.sh start
vm/qemu.sh exec 'uname -a' 'df -h'   # log in as root on the console, run, print
vm/qemu.sh console
vm/qemu.sh stop
ARCH=arm64 KERNEL=Image.gz DISK=disk-arm64.img vm/qemu.sh args   # show the QEMU command line
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `ARCH` | `arm64` | `arm64` or `x86_64` |
| `NAME` | `linux-libre-$ARCH` | instance name; state (pid, log) in `build/qemu/$NAME/` |
| `KERNEL` | — | kernel image (required) |
| `INITRD` | — | optional initrd |
| `DISK` | — | raw disk image, attached as `/dev/vda` |
| `APPEND` | `root=/dev/vda rw console=<ttyAMA0/ttyS0>` | kernel command line |
| `MEM` / `CPUS` | `256` / `1` | RAM (MiB) / cores |
| `NET` | `user` | `user` (NAT) or `none` |
| `ACCEL` | `auto` | `kvm`, `hvf`, `tcg` |
| `SNAPSHOT` | `0` | `1` = discard disk writes on exit |
| `TIMEOUT` | `60` | seconds `exec` waits for boot + commands |
| `QEMU_EXTRA` | — | extra QEMU arguments |

Commands: `run` (foreground), `start`, `console`, `exec`, `serial-path`,
`status`, `stop`, `delete`, plus `create`/`recreate`, which exist for parity
with `vm/utm.sh`. In the background the console is a host pseudo-TTY
(`-serial pty`). Its path is read from `build/qemu/$NAME/qemu.log`.

## Alpine smoke test

`make qemu-test-alpine` runs `vm/alpine-test.sh` with `RUNNER=qemu`: the same
Alpine 3.24.2 aarch64 netboot test as for UTM (details in
[utm.md](utm.md#alpine-smoke-test)). It needs internet access, and it can take
a few minutes under TCG (`TIMEOUT` defaults to 240 s).

## Troubleshooting

- **`QEMU failed to start`**: the log is printed; it is also in
  `build/qemu/$NAME/qemu.log`.
- **`kvm` requested but fails**: check `ls -l /dev/kvm` and membership of the
  `kvm` group. Use `ACCEL=tcg` to run without it.
- **Nothing on the console after `make qemu-console`**: boot messages go
  out before you attach, so press Enter to get a prompt.
