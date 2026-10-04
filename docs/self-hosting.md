# Self-hosting, stage 0: a VM that builds its own kernel

Goal: a "dev" disk image whose root filesystem contains a toolchain built from
source, so a VM booted from it can build this project's kernel (and later
everything else) by itself.

Everything here is **additive**: the normal `build` / `install` / `disk-image`
targets and the default image are unchanged. The toolchain targets build for
the **host's own architecture only** (arm64 inside `void-dev`).

## What is built

| Component | Version | Source | Why |
|-----------|---------|--------|-----|
| Linux UAPI headers | from `sources/linux-libre` | `make headers_install` | glibc and userspace headers include them |
| glibc | 2.43 | git `sources/toolchain/glibc` | headers, `crt*.o`, `libc.so` script — and the runtime |
| binutils | 2.47 | git `sources/toolchain/binutils` | `as`, `ld`, `ar`, `objcopy`, `nm`, … |
| gcc (C, C++) | 15.3.0 | git `sources/toolchain/gcc` (+ gmp/mpfr/mpc/isl via gcc's `download_prerequisites`, SHA-512 checked) | the compiler; C++ so gcc can later rebuild itself |
| GNU make | 4.4.1 | tarball, SHA-256 pinned | kernel build |
| m4 | 1.4.21 | tarball | bison runs m4 |
| bison | 3.8.2 | tarball | kernel (kconfig, dtc) |
| flex | 2.6.4 | tarball | kernel (kconfig, dtc) |
| bc | 7.1.0 (Gavin Howard's) | git `sources/toolchain/bc` | kernel (`timeconst`) |
| perl | 5.44.0 | git `sources/toolchain/perl` | kernel build scripts |

GNU make, m4, bison and flex come from release tarballs because building them
from git requires a gnulib bootstrap matched to each release.

The dev root filesystem is the normal one (`make install`) with the staged
toolchain merged on top. glibc 2.43 replaces the host glibc libraries copied
by the normal install (same ABI, newer version); everything else is unchanged.

Kernel config additions (`kernel-arm64.config`): a real-time clock
(`RTC_DRV_PL031`, `RTC_HCTOSYS`), so `make` sees correct file times, and
`NR_CPUS=8` for parallel builds.

## Steps (inside `void-dev`)

```bash
scripts/fetch-toolchain.sh                      # git sources by tag + tarballs
make toolchain TOOLCHAIN_WORK=/var/tmp/toolchain  # 1–2 h; local disk is much faster than the shared folder
make ARCH=arm64 kernel                          # rebuilds with the RTC options
make install-dev disk-image-dev TOOLCHAIN_WORK=/var/tmp/toolchain
```

Result: `disks/disk-arm64-dev.img` (8 GB, sparse; `DEV_DISK_SIZE_MB` to
change). Both root filesystems are assembled on the build machine's own disk:
the normal install in `$TOOLCHAIN_WORK/rootfs-base`, the dev rootfs in
`$TOOLCHAIN_WORK/rootfs-dev`. `install-dev` fails if any program in
`bin`/`sbin` lacks its execute bit.

**Shared-folder caveat.** When the repo is a UTM shared folder (VirtFS),
setting file modes from the Linux side fails for some files, which then
appear as `0600` there: a reinstall into `rootfs/arm64` produced a `/bin/bash`
without `+x`, and the VM powered off with `runit: … /etc/runit/1: access
denied`. Build root filesystems on local disk, also for the normal image:
`make ARCH=arm64 install disk-image ROOTFS_arm64=/var/tmp/rootfs-arm64`. `TOOLCHAIN_WORK` must be the same for
`toolchain` and `install-dev`. `make toolchain-clean` removes the work
directory and the dev rootfs.

Host tools the toolchain build itself needs (Void package names): `gcc`,
`make`, `bison`, `flex`, `texinfo` (optional), `python3` (glibc), `perl`,
`gawk`, `curl` or `wget` and `bzip2` (gcc prerequisites), `git`.

## Builder VM (on the Mac)

The builder shares the **whole repo** with the guest, so the sources are
available at `/mnt/shared` (`vm.sh` remembers the share for `recreate`):

```bash
VM_DIR=vm_tmp/selfhost MEM=4096 CPUS=4 SHARE=$PWD \
  KERNEL=sources-build/arm64/linux-libre/arch/arm64/boot/Image.gz \
  DISK=disks/disk-arm64-dev.img vm/utm.sh create
vm_tmp/selfhost/vm.sh start
vm_tmp/selfhost/vm.sh console
```

## Proof: the VM builds its own kernel

Done on 2026-10-04 in `vm_tmp/selfhost` (4 CPUs, 4 GB, UTM/hvf):

| Check | Result |
|-------|--------|
| Toolchain in the guest | gcc/g++ 15.3.0, binutils 2.47, make 4.4.1, bison 3.8.2, flex 2.6.4, m4 1.4.21, bc 7.1.0, perl 5.44.0, glibc 2.43 |
| Kernel build (in-tree, sources unpacked on the VM disk) | `Image.gz` in **73 s** |
| `.config` vs. the `void-dev` build | identical except `CONFIG_ARM64_LSUI=y`, enabled automatically by the newer binutils |
| Boot with the self-built kernel | `Linux version 7.1.3-gnu-linux-libre (root@linux-libre) (gcc (GCC) 15.3.0, GNU ld (GNU Binutils) 2.47…)` |

Fastest: unpack the sources on the VM's own disk (the share is slow for
thousands of small reads). On the Mac:

```bash
git -C sources/linux-libre archive --format=tar HEAD > build/linux-libre-src.tar
```

In the VM:

```bash
mkdir -p /build/linux-libre && tar -C /build/linux-libre -xf /mnt/shared/build/linux-libre-src.tar
cd /build/linux-libre && cp /mnt/shared/kernel-arm64.config .config
make ARCH=arm64 olddefconfig && make ARCH=arm64 -j$(nproc) Image.gz
cp arch/arm64/boot/Image.gz /mnt/shared/build/
```

Building straight from the share also works (`make -C
/mnt/shared/sources/linux-libre O=/build ARCH=arm64 …`), but took 800 s
instead of 73 s: every header is read over 9p.

### Problems found on the way (fixed)

- **Symlinks over the share.** UTM's VirtFS uses `security_model=mapped-xattr`,
  so symlinks created on the Mac (the kernel has e.g.
  `arch/arm64/tools/syscall_64.tbl -> ../../../scripts/syscall.tbl`) were
  unreadable in the guest ("Too many levels of symbolic links"), and the
  build failed with `No rule to make target …/unistd_64.h`. `vm/utm.sh` now
  adds its own `-fsdev … security_model=none` (host files as they are) on the
  shared folder.
- **`PATH` on the console.** agetty starts the shell with an empty
  environment and bash's built-in default `PATH` ends in `.`, which made gcc
  look for `cc1` relative to the current directory. The console now starts
  `/bin/console-shell`, which sets `PATH`, `HOME` and `TERM` and runs
  `bash -l`.
- **perl manual pages** landed in `/` as `*.0` files (`-Dman1dir=none`); now
  they are installed normally and removed from the staging tree.
- **File modes on the share** (see the caveat above): root filesystems are
  assembled on local disk, and `install-dev` checks every program is
  executable.

The image changes (console shell, perl) apply after rebuilding the toolchain's
perl and the dev image: in `void-dev`, `rm /var/tmp/toolchain/stamps/perl`
then `make toolchain install-dev disk-image-dev TOOLCHAIN_WORK=/var/tmp/toolchain`.

## Next

- Build the userland packages inside the VM the same way (stage 1).
- Rebuild the toolchain with itself (stage 2) — then the host toolchain is no
  longer involved.
- Move all of this into a declarative (JSON) build description.
