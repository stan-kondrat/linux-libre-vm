# Super Minimal Linux Libre — Build Plan

**Goal:** Build a stripped-down GNU/Linux system using Linux-libre kernel, GNU coreutils, glibc, and GCC — no non-free firmware, minimal attack surface, minimal footprint.

**Target:** x86_64 (amd64) on QEMU/KVM with **virtio drivers only** — no hardware-specific drivers.

---

## Phase 0 — Foundations

- [ ] Research Linux Libre deblobbing process (gx86 scripts vs linux-libre releases)
- [ ] Choose kernel source: linux-libre releases (releases.fsfla.org) or gx86 git with deblob scripts
- [ ] Review Void Linux build tools available (`gcc`, `make`, `glibc`, `coreutils`)
- [ ] Estimate disk space: ~10 GB source tarballs + ~5 GB build artifacts + ~500 MB final rootfs
- [ ] Plan disk layout: `/sources`, `/build`, `/rootfs` directories

## Phase 1 — Kernel

- [ ] Download Linux-libre tarball (latest stable)
- [ ] Apply deblobbing patches (if using mainline + scripts) or use pre-patched release
- [ ] Configure minimal kernel (see kernel-config-reference below)
- [ ] Build kernel with `make -j$(nproc)`
- [ ] Build kernel modules (minimal set, ideally zero)
- [ ] Install kernel: `arch/x86_64/boot/bzImage`
- [ ] Create initramfs (if needed: busybox-based or cpio-only minimal)
- [ ] Verify: kernel boots, no non-free module loading

### Kernel Config Goals

Target: **< 5 MB** uncompressed kernel image, **amd64 only**

```
CONFIG_MODULES=n              # monolithic, no .ko files
CONFIG_EMBEDDED=y            # allow minimal config
CONFIG_EXPERT=y              # enable hidden options
CONFIG_64BIT=y               # amd64 only
CONFIG_X86_64=y              # amd64 only

# Disable unused subsystems
CONFIG_NO_HZ=y                # tickless
CONFIG_PREEMPT_NONE=y        # server-style voluntary preempt

# Filesystems: only what you need
CONFIG_EXT4_FS=y             # (or your choice)
CONFIG_VFAT_FS=n
CONFIG_NTFS_FS=n
CONFIG_ISO9660_FS=n
CONFIG_FUSE_FS=n
CONFIG_PROC_FS=y              # required by many tools
CONFIG_TMPFS=y
CONFIG_CRAMFS=n
CONFIG_SQUASHFS=n

# Network: virtio only
CONFIG_NET=y
CONFIG_UNIX=y                 # Unix domain sockets
CONFIG_INET=y
CONFIG_TCP_IPV4=y             # IPv4 only
CONFIG_NETDEVICES=y
CONFIG_VIRTIO_NET=y           # virtio-net (QEMU/KVM)

# virtio block (QEMU/KVM disk)
CONFIG_VIRTIO=y               # virtio core
CONFIG_VIRTIO_PCI=y           # virtio-pci bus
CONFIG_VIRTIO_BLK=y           # virtio-block disk
CONFIG_SCSI=y
CONFIG_SCSI_VIRTIO=y          # virtio-scsi (optional)

# Input: only keyboard for minimal server
CONFIG_VT=y
CONFIG_CONSOLE_TRANSLATIONS=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y
CONFIG_INPUT_EVBUG=n

# Disable debug & diagnostics
CONFIG_DEBUG_INFO=n
CONFIG_DEBUG_BUGVERBOSE=n
CONFIG_MAGIC_SYSRQ=n
CONFIG_IKCONFIG=n
CONFIG_IKCONFIG_PROC=n
CONFIG_TIMER_STATS=n
CONFIG_DEBUG_LOCKDEP=n
CONFIG_DEBUG_KOBJECT=n

# Disable unused subsystems
CONFIG_SOUND=n
CONFIG_USB_SUPPORT=n
CONFIG_SERIAL_CORE=n
CONFIG_NLS=n
CONFIG_KALLSYMS=n
CONFIG_ELF_CORE=n
CONFIG_AUDIT=n
CONFIG_HARDENED_USERCOPY=n
CONFIG_FORTIFY_SOURCE=n
CONFIG_ACPI=n
CONFIG_APM=n
CONFIG_CPU_IDLE=n
CONFIG_CPU_FREQ=n
CONFIG_SUSPEND=n
CONFIG_HIBERNATION=n
CONFIG_WATCHDOG=n
CONFIG_VT_CONSOLE=y
CONFIG_HW_RANDOM=n
CONFIG_THERMAL=n
CONFIG_MEDIA_SUPPORT=n
CONFIG_DRM=n
CONFIG_AGP=n
CONFIG_VGA_ARB=n
CONFIG_HID_SUPPORT=n
CONFIG_I2C=n
CONFIG_SPI=n
CONFIG_GPIOLIB=n
CONFIG_PINCTRL=n

# Minimal block layer
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_IDE=n
CONFIG_ATA=n

# Security minimal
CONFIG_SECURITY=n
CONFIG_SECURITY_NETWORK=n
CONFIG_CC_STACKPROTECTOR=n
```

## Phase 2 — Toolchain

- [ ] Verify system GCC/glibc versions (`gcc --version`, `ldd --version`)
- [ ] Download GCC source (same major version as system, or build fresh)
- [ ] Download glibc source (matching system version)
- [ ] **Option A — Native build:** Build GCC + glibc natively in `/rootfs`
- [ ] **Option B — Cross-build:** Use existing GCC (x86_64) to build for target
- [ ] Build binutils (if not from system)
- [ ] Build GCC with `--disable-multilib` (single arch, smaller)
- [ ] Build glibc with `--disable-profile --enable-optimize`
- [ ] Verify toolchain: compile + run a minimal C program

### GCC Minimal Flags

```bash
./configure \
    --prefix=/usr \
    --disable-multilib \
    --disable-bootstrap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx \
    --disable-libitm \
    --disable-libcilkrts \
    --disable-libmpx \
    --disable-liboffloadmic \
    --disable-plugin \
    --disable-linker-plugin-opt \
    --enable-languages=c \
    --enable-threads=posix \
    --enable-tls \
    CFLAGS="-O2 -pipe -fomit-frame-pointer -s" \
    LDFLAGS="-s -Wl,--gc-sections"
```

### glibc Minimal Flags

```bash
echo "libc_cv_forced_unwind=yes" > configparms
echo "libc_cv_c_cleanup=yes" >> configparms

./configure \
    --prefix=/usr \
    --enable-kernel=6.0 \
    --disable-profile \
    --enable-obsolete-rpc \
    --disable-nsswitch-plugin \
    --disable-assert \
    --disable-login \
    --disable-sulogin \
    --disable-syslog \
    --without-headers \
    --disable-werror \
    --enable-optimize='-O2'
```

## Phase 3 — Minimal Userland

- [ ] Build minimal `coreutils` (GNU coreutils, stripped)
- [ ] Build minimal `bash` (or dash if POSIX shell acceptable with GNU utils)
- [ ] Build `grep`, `sed`, `awk` (minimal versions)
- [ ] Build `findutils`
- [ ] Build `diffutils`
- [ ] Build `file`
- [ ] Build `gzip`
- [ ] Build `tar`
- [ ] Build `util-linux` (minimal: `mount`, `umount`, `swapon`, `fdisk`, `lsblk`)
- [ ] Build `procps-ng` (minimal: `ps`, `kill`, `top`, `watch`, `pgrep`, `pkill`, `free`)
- [ ] Build `inetutils` or minimal `iproute2` (only what you need: `ip`, `ss`)
- [ ] Build minimal `dhcpcd` or `udhcpc` (busybox or standalone)
- [ ] Build `openssh` (optional, minimal)
- [ ] Build `vim` (required)

### Build Flags for All Packages

Apply these flags to EVERY package build for minimalism:

```bash
CFLAGS="-O2 -pipe -fomit-frame-pointer -s"
LDFLAGS="-s -Wl,--as-needed,-z,relro,-z,now"
# Strip all binaries
STRIP=binary --strip-unneeded --strip-debug
# Disable features you don't need
```

### coreutils Minimal Build

```bash
./configure \
    --prefix=/usr \
    --enable-no-install-program= \
    --with-packager="minimal" \
    --disable-nls \
    --disable-assert \
    --without-gmp \
    --without-selinux \
    --disable-silent-rules \
    --host=$(./config.guess) \
    CFLAGS="-O2 -pipe -fomit-frame-pointer -s" \
    LDFLAGS="-s -Wl,--as-needed"
```

Then **selectively remove unneeded programs** during `make install`:

| Typically safe to remove | Often needed |
|--------------------------|-------------|
| `[, arch, b2sum, base32, base64, basename, cat, chcon, chgrp, chmod, chown, chroot, cksum, comm, cp, csplit, cut, date, dd, df, dir, dircolors, dirname, du, echo, env, expand, expr, factor, false, fmt, fold, groups, head, hostid, hostname, id, install, join, kill, link, ln, logname, ls, md5sum, mkdir, mkfifo, mknod, mktemp, mv, nice, nl, nohup, nproc, numfmt, od, paste, pathchk, pr, printenv, printf, ptx, pwd, readlink, rm, rmdir, runcon, sha*sum, seq, shred, shuf, sleep, sort, split, stat, stdbuf, stty, sum, sync, tac, tail, tee, test, timeout, touch, tr, true, truncate, tsort, tty, uname, unexpand, uniq, unlink, users, vdir, wc, who, whoami, yes` | `cat, chmod, cp, date, dd, df, grep, ls, mkdir, mv, rm, sed, sh, sort, sync` |

## Phase 4 — Init System

- [ ] Choose init: **runit** (recommended) or simple `sh` based init or `OpenRC`
- [ ] Build chosen init system
- [ ] Define runlevel/service structure
- [ ] Create minimal `/etc` skeleton:

```
/etc/
├── rc.conf
├── fstab
├── passwd
├── group
├── shadow
├── hostname
├── hosts
├── resolv.conf
├── inittab      (if sysvinit)
├── runit/
│   ├── runit/
│   │   ├── runsvdir/
│   │   │   └── default/
│   │   │       └── @ ->
│   │   └── runsvchpfd/
│   └── sv/
│       ├── devfs/
│       ├── udhcpd/
│       └── getty-tty*
└── profile
```

- [ ] Create minimal device tree (`/dev`) — use `mknod` or `devtmpfs`
- [ ] Configure `getty` on console

## Phase 5 — Runtime Minimalism

- [ ] **Strip everything.** Run `strip -s` on every binary in `/rootfs`
- [ ] Remove debug symbols, `.comment`, `.note` sections
- [ ] Remove locale data: keep only `en_US.UTF-8` or minimal set
- [ ] Remove man pages (or keep `man` binary but no `man.db`)
- [ ] Remove info pages
- [ ] Remove documentation: `/usr/share/doc`, `/usr/share/man`
- [ ] Compile binaries with `--static` where possible (reduces attack surface, no PLT)
- [ ] Remove shared libraries you don't need (check with `ldd`)
- [ ] Remove `*.py`, `*.pl` scripts that have binary equivalents
- [ ] Configure `/etc/shadow` (no password or minimal)
- [ ] Remove setuid binaries you don't need
- [ ] Review `/etc/passwd` — remove accounts you don't need

### Strip Script

```bash
#!/bin/sh
echo "Stripping and minimizing..."
find /rootfs/usr/bin /rootfs/usr/sbin /rootfs/bin /rootfs/sbin -type f -exec strip -s {} \; 2>/dev/null
find /rootfs -name "*.py" -delete 2>/dev/null
find /rootfs -name "*.pod" -delete 2>/dev/null
rm -rf /rootfs/usr/share/doc
rm -rf /rootfs/usr/share/locale
rm -rf /rootfs/usr/share/i18n
rm -rf /rootfs/usr/share/zoneinfo  # keep one
rm -rf /rootfs/usr/share/man
rm -rf /rootfs/usr/share/info
rm -rf /rootfs/var/cache
rm -rf /rootfs/tmp
```

## Phase 5.5 — QEMU Disk Image (MBR)

- [ ] Create raw disk image file: `dd if=/dev/zero of=disk.img bs=1M count=<SIZE> status=progress` (e.g. 256, 512, 1024)
- [ ] Partition image with MBR (msdos label):
  - Partition 1: bootable, type `83` (Linux), starts at sector 2048 (1 MB alignment)
  - Use `fdisk disk.img` or `sfdisk` for scriptable partition table
- [ ] Zero the first 446 bytes of MBR (boot code area) or write your own bootloader there
- [ ] Set up loopback device: `losetup -fP disk.img` → `/dev/loop0`
- [ ] Format partition 1: `mkfs.ext4 -F /dev/loop0p1 -L minimal-libre`
- [ ] Mount partition: `mount /dev/loop0p1 /mnt/rootfs-image`
- [ ] Copy rootfs contents: `cp -a /rootfs/. /mnt/rootfs-image/`
- [ ] Install GRUB to MBR of disk image:
  ```bash
  mkdir -p /mnt/rootfs-image/boot/grub
  # For i386-pc target (BIOS boot)
  grub-install \
      --target=i386-pc \
      --boot-directory=/mnt/rootfs-image/boot \
      --no-floppy \
      --modules="part_msdos ext2" \
      /dev/loop0
  ```
- [ ] Create `grub.cfg`:
  ```
  menuentry "Linux Libre" {
      linux /boot/vmlinuz root=/dev/vda1 ro
      initrd /boot/initrd.img
  }
  ```
- [ ] Unmount: `umount /mnt/rootfs-image`, `losetup -d /dev/loop0`
- [ ] Verify partition table: `fdisk -l disk.img`
- [ ] Test with QEMU:
  ```bash
  qemu-system-x86_64 \
      -drive file=disk.img,format=raw,if=virtio \
      -kernel bzImage \
      -append "root=/dev/vda1 ro" \
      -initrd initrd.img \
      -m 256M \
      -net none \
      -nographic
  # OR full VM boot from disk:
  qemu-system-x86_64 \
      -drive file=disk.img,format=raw,if=virtio \
      -m 256M \
      -net none \
      -nographic
  ```

### MBR Partition Layout

```
disk.img
├── MBR (sector 0, 512 bytes)
│   ├── Boot code (446 bytes, zeroed or syslinux)
│   ├── Partition table (64 bytes, 4 x 16-byte entries)
│   └── Magic number (0xAA55)
├── [empty sectors 1-2047] (1 MB gap)
└── Partition 1 (sectors 2048-end, type 0x83 Linux)
    ├── /boot/grub/grub.cfg
    ├── /boot/vmlinuz
    ├── /boot/initrd.img
    ├── / (minimal rootfs)
    └── /dev (minimal devtmpfs)
```

### Bootloader Options

Choose **one** of these three approaches:

#### Option 1 — GRUB2 (large ~300KB, full features)
```bash
./configure --target=i386-pc --prefix=/usr --disable-efiemu
make
grub-install --target=i386-pc --boot-directory=/mnt/rootfs-image/boot --no-floppy \
    --modules="part_msdos ext2" /dev/loop0
```

#### Option 2 — syslinux (medium ~50KB, simple config)
```bash
dd if=/usr/share/syslinux/mbr.bin of=disk.img conv=notrunc
extlinux --install /mnt/rootfs-image/boot
# create boot/extlinux.conf with default options
```

#### Option 3 — Custom ASM bootsector (~300 bytes, no dependencies)

**No GRUB needed. No shell. No config file. No modules.**

The Linux bzImage kernel already contains a built-in 16-bit bootsector stub. Your custom bootsector (first 512 bytes of disk MBR) only needs to:
1. **Read kernel from disk** (LBA via BIOS INT 0x13 / AH=0x42)
2. **Set up minimal GDT** (code + data segment descriptors)
3. **Enable PAE + paging** (identity-map first 1GB)
4. **Enable long mode** (EFER.LME + CR0.PG)
5. **Jump to kernel entry** at 0x100000

Assemble + install:
```bash
nasm -f bin -o bootsect.bin boot/boot_sect.asm
dd if=bootsect.bin of=disk.img conv=notrunc
```

Reference: `boot/boot_sect.asm` (~300 bytes stripped, fully commented)

### Why NOT GRUB?

| | GRUB2 | Custom ASM |
|---|---|---|
| Size | ~300KB | ~300 bytes |
| Config file | `grub.cfg` | None |
| Modules | `part_msdos`, `ext2`, etc. | None |
| Dependencies | GRUB source, build chain | nasm only |
| Attack surface | Large C code | ~200 lines ASM |
| Educational | Hidden complexity | Transparent |
| Trusted boot | Chain-loaded, unsigned | Direct kernel load |

## Phase 6 — Verification & Packaging

- [ ] Test in VM (QEMU): boot kernel + initramfs/rootfs
- [ ] Measure kernel size: `size vmlinux` or `ls -lh`
- [ ] Measure rootfs size: `du -sh rootfs`
- [ ] Measure RAM usage at boot: boot to single-user, check `free -m`
- [ ] Count running processes: `ps aux`
- [ ] Check open files: `lsof`
- [ ] Check network sockets: `ss -tulpn`
- [ ] Verify no non-free firmware loaded: `dmesg | grep -i "firmware\|blob\|nonfree"`
- [ ] Verify no orphaned libraries: `ldd /bin/* /usr/bin/*`
- [ ] Package rootfs: `tar -cvzf ../minimal-libre.tar.gz .`

## Phase 7 — Hardening

- [ ] Enable `prctl(PR_SET_DUMPABLE, 0)` where supported
- [ ] Set `chmod 0` on sensitive `/proc` entries
- [ ] Review `sysctl` settings (network, memory, kernel params)
- [ ] Consider `grsecurity` patches or `PaX` (if available for kernel version)
- [ ] Consider `seccomp` filter for minimal syscall whitelist
- [ ] Review firewall rules (if `iptables` present)

---

## Reference: Build Order (Dependency Graph)

```
Phase 1 (Kernel)         Phase 2 (Toolchain)        Phase 3 (Userland)
─────────────────        ──────────────────         ──────────────────
linux-libre              gcc (stage1)                bash
  ├─ kernel config         ├─ binutils                ├─ coreutils
  ├─ make bzImage           ├─ glibc                   ├─ grep
  └─ make modules           └─ libgcc                  ├─ sed
                                                    ├─ awk
Phase 4 (Init)                                    ├─ findutils
─────────────────                                 ├─ tar
runit                                            ├─ gzip
  ├─ chpst                                          └─ (other utils)
  ├─ runsvdir                                     procps-ng
  └─ runsv                                         ├─ ps
                                                   └─ kill
Phase 5 (Integration)                            iproute2
─────────────────                                ├─ ip
fstab                                            └─ ss
hostname                                         dhcpcd
passwd/group                                     openssh (optional)
profile
/dev nodes

Phase 6 (Test & Package)
─────────────────────────
QEMU VM boot test
Size measurement
dmesg verification
```

---

## Targets

| Metric | Target |
|--------|--------|
| Kernel image (bzImage/zImage) | < 5 MB |
| Kernel + modules | < 10 MB |
| Rootfs (uncompressed) | < 100 MB |
| Rootfs (compressed) | < 20 MB |
| RAM at idle | < 64 MB |
| Running processes | < 15 |
| Non-free blobs loaded | 0 |
| Open network sockets (idle) | 0 (or minimal) |

---

## Notes

- Linux-libre deblobbing: scripts at https://git.savannah.gnu.org/cgit/configs.git/ and https://www.gitlab.com/linux-libre/linux-libre
- Void Linux uses `xbps`, can use `xbps-src` to build packages if cross-compiling for amd64
- For the GCC/glibc build, follow LFS chapter 5/6 closely (linuxfromscratch.org)
- **Target platform:** QEMU/KVM with virtio (no physical hardware drivers needed)
- **Virtio only:** CONFIG_VIRTIO_NET, CONFIG_VIRTIO_BLK, CONFIG_VIRTIO_PCI — no E1000, R8169, USB, etc.