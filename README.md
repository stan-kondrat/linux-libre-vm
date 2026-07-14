# Super Minimal Linux Libre

Build a stripped-down GNU/Linux system from scratch using Linux-libre kernel, GNU coreutils, glibc, and GCC — no non-free firmware, minimal footprint, minimal attack surface.

**Status:** Both x86_64 and arm64 boot to shell with DHCP networking ✅

**Target:** x86_64 (amd64, QEMU q35 + virtio-pci), arm64 (aarch64, QEMU virt + virtio-pci).

**Build host:** x86_64 or aarch64 Linux — auto-detected

---

## Quick Start

```bash
# Prerequisites: cross-compiler, build tools, QEMU
# On x86_64 host: xbps-install -S cross-aarch64-linux-gnu cross-aarch64-linux-gnu-libc
# (or equivalent for your distro)

git submodule update --init --recursive

# Full build + boot
make build              # all userland + kernel, both arches
make install            # install to rootfs/
make disk-image         # create ext4 images (no root needed)
make qemu-x86_64        # boot x86_64 in QEMU (Ctrl-C to exit)
make qemu-arm64         # boot arm64 in QEMU (Ctrl-C to exit)
```

---

## Git Submodules

All third-party sources are managed as git submodules under `sources/` — **never modified directly**.

### Submodule URLs

| Package | Repository | Version | Notes |
|---------|-----------|---------|-------|
| linux-libre | `git://linux-libre.fsfla.org/releases.git` | `v7.1.3-gnu` | deblobbed kernel |
| bash | `https://git.savannah.gnu.org/git/bash.git` | `bash-5.3` | GNU bash shell |
| coreutils | `https://git.savannah.gnu.org/git/coreutils.git` | `v9.6` | GNU coreutils |
| grep | `https://git.savannah.gnu.org/git/grep.git` | `v3.11` | GNU grep |
| sed | `https://git.savannah.gnu.org/git/sed.git` | `v4.9` | GNU sed |
| gawk | `https://git.savannah.gnu.org/git/gawk.git` | `gawk-5.4.1` | GNU awk |
| findutils | `https://git.savannah.gnu.org/git/findutils.git` | `v4.10.0` | GNU findutils |
| diffutils | `https://git.savannah.gnu.org/git/diffutils.git` | `v3.10` | GNU diffutils |
| gzip | `https://git.savannah.gnu.org/git/gzip.git` | `v1.13` | GNU gzip |
| tar | `https://git.savannah.gnu.org/git/tar.git` | `v1.35` | GNU tar |
| vim | `https://github.com/vim/vim.git` | `v9.2.0725` | vim editor |
| iproute2 | `https://git.kernel.org/pub/scm/network/iproute2/iproute2.git` | `v7.1.0` | network tools |
| procps-ng | `https://gitlab.com/procps-ng/procps.git` | `v4.0.5` | procps tools |
| util-linux | `https://git.kernel.org/pub/scm/utils/util-linux/util-linux.git` | `v2.40.4` | system utilities |
| runit | `https://github.com/g-pape/runit/` | `v2.3.1` | init system |
| dhcpcd | `https://github.com/NetworkConfiguration/dhcpcd.git` | `v10.3.2` | DHCP client |

GCC, glibc, and binutils are host-provided (sources included for reference only).

---

## File Structure

```
linux-libre-vm/
├── Makefile                      main entry — includes mk/*.mk
├── mk/                           modular Makefile fragments
│   ├── 00-vars.mk               variables, directories, flags
│   ├── 01-setup.mk              phony targets, build-dirs, check-env
│   ├── 02-fake-bin.mk           stub scripts for missing host tools
│   ├── 03-source-prep.mk        copy + patch pipeline
│   ├── 04-build-rules.mk        per-package build rule macros
│   ├── 05-packages.mk           package declarations, install, libs
│   ├── 07-kernel.mk             Linux-libre kernel (x86_64 + arm64)
│   ├── 08-clean-help.mk         clean, distclean, help
│   ├── 09-init.mk               init system + /etc skeleton
│   ├── 10-disk.mk               disk image + QEMU + test targets
│   └── tee-log.sh               LOG=1 tee wrapper
│
├── sources/                      git submodules (NEVER modified)
│   └── <pkg>/                    per-package source trees
│
├── sources-patched/              patched source trees (gitignored)
├── sources-build/                per-arch build output (gitignored)
│   ├── x86_64/<pkg>/            x86_64 build directories
│   └── arm64/<pkg>/             arm64 build directories
│
├── sources-patches/              per-package patch files
├── build/                        shared build infrastructure (gitignored)
├── rootfs/                       staging root filesystems (gitignored)
│   ├── x86_64/                  x86_64 root (67M)
│   └── arm64/                   arm64 root (62M)
├── disks/                        bootable disk images (gitignored)
│   ├── disk-x86_64.img          x86_64 disk image (84M)
│   └── disk-arm64.img           arm64 disk image (72M)
├── build-logs/                   per-target build logs (gitignored)
│
├── kernel-x86_64.config         x86_64 kernel config (super minimal, PCI)
├── kernel-arm64.config          arm64 kernel config (super minimal)
│
├── templates/                    init system template files (tracked in git)
│   ├── etc/                     /etc skeleton
│   │   ├── fstab, passwd, group, shadow, hostname, hosts, resolv.conf
│   │   ├── ld.so.conf
│   │   └── runit/{1,2,3,ctrlaltdel}
│   └── bin/                     poweroff, reboot, halt, shutdown scripts
│
└── README.md                    this file
```

---

## Build System

The Makefile orchestrates all builds through modular fragments under `mk/`.

### Prerequisites

| Package | Purpose |
|---------|---------|
| make | Build system driver |
| gcc | Host native compiler |
| autoconf / automake | Regenerating configure scripts |
| gettext | i18n framework (gnulib bootstrap) |
| texinfo | `makeinfo` for documentation |
| patch | Applying source patches |
| xz | Compression (gnulib bootstrap) |
| rsync | Copying source trees |
| bc | Kernel build (`timeconst.h`) |
| elfutils-devel | `libelf` headers (kernel objtool) |
| qemu-system-x86_64 / qemu-system-aarch64 | VM testing |

**Cross-compiler** (depending on host arch):

| Host | Install |
|------|---------|
| x86_64 | `gcc-aarch64-linux-gnu`, `linux-libc-dev-arm64-cross` (Debian) |
| aarch64 | `gcc-x86-64-linux-gnu` (Debian) |

### Usage

```bash
make help                          # all targets

# Build
make build                         # all userland + kernel, both targets
make bash                          # one package, both targets
make ARCH=x86_64 build-coreutils   # one package, one arch
make kernel                        # both kernels

# Install to rootfs
make install                       # everything
make ARCH=x86_64 install           # one arch

# Disk image (ext4 via mke2fs -d — no root/guestfish needed)
make disk-image                    # both arches
make disk-image-x86_64

# QEMU boot
make qemu-x86_64                   # boots to bash shell (QEMU q35 + virtio-pci)
make qemu-arm64                    # boots to bash shell (QEMU virt + virtio-pci)

# Tests
make test-dhcpcd-x86_64            # DHCP test (10s timeout)
make test-shutdown-x86_64          # shutdown test (6s timeout)
make test                          # all tests

# Logging
make build LOG=1                   # → build-logs/build.log

# Stripping
make STRIP=0 install               # skip binary stripping
```

### Build Pipeline

```
sources/<pkg>  ──copy+patch──→  sources-patched/<pkg>/  (once)
                                       │
                                ┌──────┴──────┐
                                ▼              ▼
                    sources-build/x86_64/   sources-build/arm64/
```

`make install` then copies built binaries to `rootfs/<arch>/`, runs strip, consolidates all binaries to `/bin`, copies required shared libraries, and creates `/etc` skeleton from templates.

### Auto-detection

- **On x86_64 host:** x86_64 = native `gcc`, arm64 = `aarch64-linux-gnu-` cross
- **On aarch64 host:** arm64 = native `gcc`, x86_64 = `x86_64-linux-gnu-` cross

### Packages (15 userland + 1 kernel)

coreutils bash grep sed gawk findutils diffutils gzip tar vim iproute2 procps-ng util-linux runit dhcpcd

### Patches

Patches live in `sources-patches/<pkg>/` and apply once during copy to `sources-patched/`.

| Package | Patch | Reason |
|---------|-------|--------|
| gzip | rename `head` → `gzip_head` | Collides with aarch64 `sigcontext.h` |
| tar | remove `po` from SUBDIRS | No gettext needed |
| util-linux | remove `po` from SUBDIRS | No gettext needed |
| procps-ng | `echo -e` → `printf` in Makefile.am | POSIX sh compatibility |

---

## Verification

### x86_64 Boot Diagnostics

```
Hostname: linux-libre
Kernel: 7.1.3-gnu-linux-libre
Memory: 245MB total, ~21MB used
Processes: 34
Binaries: 297 in /bin
Loopback: 127.0.0.1/8
DHCP: 10.0.2.15/24 on eth0
Shell: bash-5.3#
```

### arm64 Boot Diagnostics

```
Hostname: linux-libre
Kernel: 7.1.3-gnu-linux-libre
Memory: 249MB total, ~14MB used
Processes: 36
Binaries: 287 in /bin
Shell: bash-5.3#
```

### Hardening

| Item | Status |
|------|--------|
| Setuid binaries | ✅ None (no shadow/sudo/PAM) |
| /proc mount | ✅ `nosuid,noexec,nodev` |
| Seccomp | ✅ Built into both kernels (`CONFIG_SECCOMP_FILTER=y`) |
| Non-free blobs | 0 ✅ |

---

## Targets

| Metric | Target | Current |
|--------|--------|---------|
| Kernel image | < 3 MB | x86_64: 3.3M, arm64: 2.9M |
| Rootfs (uncompressed) | < 50 MB | x86_64: 67M, arm64: 62M |
| RAM at idle | < 64 MB | x86_64: ~21M, arm64: ~14M ✅ |
| Running processes | < 15 | x86_64: 34, arm64: 36 |
| Non-free blobs | 0 | 0 ✅ |

---

## Architecture

- Kernel: Linux-libre → directly booted by QEMU (`-kernel bzImage` / `-kernel Image.gz`)
- x86_64 machine: QEMU q35 with virtio-pci (block + network), no ACPI
- arm64 machine: QEMU virt with virtio-mmio (block) + virtio-pci (network)
- Init: runit (statically linked) → PID 1
- Services: getty on serial console (ttyS0 / ttyAMA0)
- Rootfs: ext4 image, created via `mke2fs -d` (no loop devices, no root)
- Boot: QEMU + kernel + raw disk image, no bootloader needed
- Networking: QEMU slirp user-mode, dhcpcd
- Library path: `/usr/lib64 → /lib` for ld-linux compatibility
