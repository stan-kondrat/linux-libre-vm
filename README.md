# Super Minimal Linux Libre

Build a stripped-down GNU/Linux system from scratch using Linux-libre kernel, GNU coreutils, glibc, and GCC — no non-free firmware, minimal footprint, minimal attack surface.

**Target:** x86_64 (amd64) on QEMU/KVM with virtio drivers only.

**Build host:** Void Linux (aarch64)

---

## File Structure

```
/mnt/shared/projects/linux-vm/
│
├── README.md                    this file
├── TODO.md                      detailed build plan (phases 0-7)
│
├── sources/                     source tarballs & git checkouts
│   ├── linux-libre/             Linux-libre kernel source
│   │   ├── .config              kernel config (amd64, virtio-only)
│   │   └── arch/x86_64/boot/bzImage  (built kernel)
│   │
│   ├── gcc/                     GCC source
│   ├── glibc/                   glibc source
│   ├── binutils/                binutils source (optional)
│   └── packages/                 other source packages
│       ├── bash/
│       ├── coreutils/
│       ├── grep/
│       ├── sed/
│       ├── awk/
│       ├── findutils/
│       ├── gzip/
│       ├── tar/
│       ├── vim/
│       ├── runit/
│       ├── procps-ng/
│       ├── iproute2/
│       ├── dhcpcd/
│       ├── util-linux/
│       └── diffutils/
│
├── build/                       build artifacts (can be discarded after)
│   ├── linux-libre/             kernel build dir
│   ├── gcc/                     gcc build dir
│   ├── glibc/                   glibc build dir
│   └── packages/
│       ├── bash/
│       ├── coreutils/
│       └── ...                   (each package built here)
│
├── rootfs/                      final root filesystem (the target system)
│   ├── bin/                     essential user binaries (stripped)
│   │   ├── bash
│   │   ├── sh -> bash
│   │   ├── cat, cp, date, dd, df, echo, grep, ls, mkdir
│   │   ├── mv, rm, sed, sort, sync, touch, true, false, ...
│   │   ├── ps, kill, free, pgrep, pkill
│   │   ├── ip, ss, dhcpcd
│   │   ├── vim
│   │   └── ... (minimal set only)
│   │
│   ├── sbin/                    system binaries
│   │   ├── init                  runit init
│   │   ├── runsvdir
│   │   ├── runsv
│   │   ├── mount, umount        (from util-linux)
│   │   ├── fdisk, lsblk         (from util-linux)
│   │   └── getty
│   │
│   ├── usr/
│   │   ├── bin/                 additional utilities
│   │   │   ├── chgrp, chmod, chown
│   │   │   ├── tar, gzip
│   │   │   ├── find, xargs
│   │   │   ├── awk, diff
│   │   │   └── locale           (en_US only)
│   │   │
│   │   ├── sbin/
│   │   │   ├── mkswap
│   │   │   └── swapon
│   │   │
│   │   ├── lib/
│   │   │   ├── ld-linux-x86_64.so.2    (glibc dynamic linker)
│   │   │   ├── libc.so.6               (glibc)
│   │   │   └── libm.so.6
│   │   │
│   │   ├── share/
│   │   │   ├── locale/          (en_US.UTF-8 only, stripped)
│   │   │   └── zoneinfo/        (UTC only)
│   │   │
│   │   └── include/             (minimal: libc headers)
│   │
│   ├── etc/
│   │   ├── passwd               root:x:0:0::/:
│   │   ├── group                root:x:0:
│   │   ├── shadow               (no password or minimal)
│   │   ├── fstab                /dev/vda1 / ext4 defaults 0 1
│   │   ├── hostname             minimal-libre
│   │   ├── hosts                127.0.0.1 localhost
│   │   ├── resolv.conf          nameserver 8.8.8.8
│   │   ├── profile              PATH, PS1
│   │   └── runit/               runit service directories
│   │       └── sv/
│   │           ├── devfs/
│   │           │   ├── run
│   │           │   └── finish
│   │           ├── udhcpd/
│   │           │   ├── run
│   │           │   └── finish
│   │           └── getty-ttyS0/
│   │               ├── run
│   │               └── finish
│   │
│   ├── dev/                     (minimal set or devtmpfs)
│   │   ├── zero
│   │   ├── null
│   │   ├── console
│   │   ├── tty, ttyS0
│   │   ├── urandom
│   │   └── vda, vda1            (virtio block device)
│   │
│   ├── proc/                     (empty, kernel populated)
│   ├── sys/                      (empty, kernel populated)
│   ├── run/                      (runit runtime sockets)
│   ├── var/
│   │   ├── service/              (runit supervised services)
│   │   ├── log/
│   │   │   └── .empty
│   │   └── run/
│   │       └── .empty
│   ├── tmp/                      (empty)
│   └── boot/
│       └── (bootloader config if not embedded in MBR)
│
├── boot/                         bootloader sources
│   └── boot_sect.asm             custom ASM bootsector (nasm)
│       └── bootsect.bin          (assembled output)
│
├── disk.img                      raw disk image (MBR partitioned)
│   ├── MBR (sector 0, 512B)
│   │   ├── Boot code (446B: custom ASM bootsector)
│   │   ├── Partition table (64B)
│   │   └── Magic 0xAA55
│   ├── [gap sectors 1-2047]      (1 MB alignment)
│   └── Partition 1 (sectors 2048+, type 0x83 Linux)
│       ├── /boot/vmlinuz         (kernel bzImage)
│       ├── /boot/initrd.img      (initramfs, optional)
│       ├── /boot/grub/           (if GRUB bootloader chosen)
│       └── / (rootfs contents)
│
├── minimal-libre.tar.gz          packaged rootfs
├── strip.sh                      post-build stripping script
└── qemu-test.sh                  QEMU launch script
```

---

## Build Phases

| Phase | Description |
|-------|-------------|
| 0 | Foundations — research, disk layout |
| 1 | Linux-libre kernel (< 5 MB, virtio-only) |
| 2 | GCC + glibc toolchain |
| 3 | Minimal GNU userland + vim |
| 4 | runit init + `/etc` skeleton |
| 5 | Strip, minimize, harden |
| 5.5 | MBR disk image + bootloader |
| 6 | QEMU verification + packaging |
| 7 | Hardening (seccomp, sysctl) |

Full details: `TODO.md`

---

## Targets

| Metric | Target |
|--------|--------|
| Kernel image | < 5 MB |
| Rootfs (uncompressed) | < 100 MB |
| Rootfs (compressed) | < 20 MB |
| RAM at idle | < 64 MB |
| Running processes | < 15 |
| Non-free blobs | 0 |

---

## Quick Links

- Linux Libre: https://www/linux-libre.fsfla.org/
- Void Linux: https://voidlinux.org/
- Linux From Scratch: https://www.linuxfromscratch.org/
- runit: http://smarden.org/runit/