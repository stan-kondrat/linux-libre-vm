# Cross toolchains

`mk/15-cross-toolchain.mk` builds GNU cross toolchains (binutils, gcc C/C++,
glibc, Linux UAPI headers) from the same pinned sources as the native
[self-hosting toolchain](self-hosting.md). It is additive: no existing target
changes.

There are two hosts, `arm64` and `x86_64` (the two VM types), and one fixed
list of targets, `CROSS_TARGETS`. Both dev images contain every target's
toolchain, so a dev VM of either architecture compiles for all of them:

| Host (dev image) | Native | Cross, under `/opt/cross/<triplet>` |
|------------------|--------|-------------------------------------|
| `arm64` | gcc in `/usr` | `aarch64-linux-gnu`, `x86_64-linux-gnu`, `armv6-linux-gnueabihf`, `armv7-linux-gnueabihf`, `riscv64-linux-gnu`, `i686-linux-gnu`, `i686-sse2-linux-gnu` |
| `x86_64` | gcc in `/usr` | the same seven |

The VMs only run arm64 and x86_64. The other targets exist so a dev VM can
compile for them (for eclogite-linux); their binaries are checked, not run.

A gcc build targets exactly one architecture/ABI, so each target is its own
toolchain (binutils, gcc, glibc sysroot). The target matching the host is
built too: it links against its own sysroot, never against the dev image's
libraries.

## Targets

| `TARGET` | Triplet | gcc defaults | For |
|----------|---------|--------------|-----|
| `arm64` | `aarch64-linux-gnu` | — | arm64 |
| `x86_64` | `x86_64-linux-gnu` | — | x86-64 |
| `armv6` | `armv6-linux-gnueabihf` | `--with-arch=armv6 --with-fpu=vfp --with-float=hard --with-mode=arm` | BCM2835 (Raspberry Pi 1 / Zero) |
| `armv7` | `armv7-linux-gnueabihf` | `--with-arch=armv7-a --with-fpu=vfpv3-d16 --with-float=hard --with-mode=thumb` | ARMv7-A, the Debian armhf baseline |
| `riscv64` | `riscv64-linux-gnu` | `--with-arch=rv64gc --with-abi=lp64d` | RV64GC, the Linux distribution baseline |
| `i686` | `i686-linux-gnu` | `--with-arch=i686 --with-tune=generic` | 32-bit x86 since the Pentium Pro, x87 floating point |
| `i686-sse2` | `i686-sse2-linux-gnu` | `--with-arch=pentium4 --with-fpmath=sse --with-tune=generic` | 32-bit x86 with SSE2, the baseline of current 32-bit distributions |

Naming: the CPU field says what the instruction set is (`armv6`, `armv7`,
`i686`, `riscv64`); the vendor field marks a variant only when two toolchains
would otherwise share a triplet (`i686-sse2-linux-gnu` next to
`i686-linux-gnu`).

The two 32-bit ARM targets put the CPU into the triplet so both can be
installed side by side; they share the hard-float ABI and dynamic linker
(`/lib/ld-linux-armhf.so.3`). Adding a target means adding its `XT_*_<t>`
variables (triplet, kernel arch, gcc options, expected ELF machine and
attributes, predefined macros) and listing it in `CROSS_TARGETS`.

## Sources

`scripts/fetch-toolchain.sh` (run on the host, which has git and network)
fetches everything; the build itself is offline:

- binutils 2.47, gcc 15.3.0, glibc 2.43: git submodules under
  `sources/toolchain/`;
- gmp 6.2.1, mpfr 4.1.0, mpc 1.2.1, isl 0.24: the versions gcc's
  `contrib/download_prerequisites` names, verified against the SHA-512 sums gcc
  ships. These used to be downloaded during the native gcc build; both builds
  now use the fetched copies;
- CPython 3.14.8 (git `sources/toolchain/python`): glibc's build needs python3.
  Dev images built from now on contain it; on a host without one, the cross
  build first compiles it into `$CROSS_WORK/host-python`, a build tool only.

The dev image has no git, bzip2 or xz. The fetch script therefore also unpacks
the `.tar.bz2`/`.tar.xz` archives next to themselves in `sources/toolchain/dist/`,
and source trees are copied from the submodule checkouts with `tar` when git is
missing, every file given the same timestamp (as `git archive` does), so no
generated file looks out of date.

## Steps

On the host:

```bash
scripts/fetch-toolchain.sh
vm_tmp/selfhost/vm.sh start
```

In the dev VM (repo shared at `/mnt/shared`; build on the VM's own disk):

```bash
cd /mnt/shared
make cross-toolchain cross-toolchain-test TARGET=armv6 CROSS_WORK=/build/cross
make cross-toolchain-dist TARGET=armv6 CROSS_WORK=/build/cross CROSS_DIST=/mnt/shared/build/cross
```

`make cross-toolchains` builds and tests every target in `CROSS_TARGETS`;
`make cross-toolchain-all` also packages each one.

`make install-dev` runs `cross-toolchains` and copies each prefix into the dev
root filesystem as `/opt/cross/<triplet>`; `/etc/profile` puts their `bin`
directories on `PATH`. Cross work goes to `$TOOLCHAIN_WORK/cross` by default
(`CROSS_WORK`).

`TC_SRC=<dir>` builds from a copy of `sources/toolchain` elsewhere; inside the
VM, copying it to local disk once saves the slow 9p reads for every target.

The sequence per target: binutils → Linux headers (`headers_install
ARCH=<kernel arch>`) → gcc stage 1 (C only, static libgcc, no libc) → glibc,
compiled by stage 1 → gcc (C, C++, shared libgcc, libstdc++) against that
glibc. Source and build directories are removed after each step
(`CROSS_KEEP_BUILD=1` keeps them), so one target fits on the dev image's 8 GB
disk.

## Layout and artifact

```text
$CROSS_WORK/<target>/<triplet>/            prefix (the artifact)
  bin/<triplet>-gcc, -g++, -ld, -readelf …
  <triplet>/sysroot/                       glibc + Linux headers for the target
  BUILD-INFO                               triplet, host, gcc options, versions
```

The sysroot lives inside the prefix, so gcc and ld find it relative to their
own location: the toolchain works from wherever it is unpacked.

`cross-toolchain-dist` writes `cross-<triplet>.<host arch>.tar.gz` and a
`.sha256` file. The tarball is deterministic (sorted names, owner 0, mtime 0,
`gzip -n`) given identical build output.

`cross-toolchain-test` compiles a dynamically linked C program, a static one
and a threaded C++ program, and checks each binary's ELF machine and that its
program interpreter exists in the sysroot. Per target it also checks ELF
attributes (`Tag_CPU_arch: v6`/`v7` and the VFP hard-float ABI on ARM, the
double-float ABI on riscv64) and the baseline gcc predefines (`__SSE2__` and
`__SSE_MATH__` on `i686-sse2`, no `__SSE2__` on `i686`).

## Results

All seven targets, built in the `selfhost` VM (dev image, arm64 host on Apple
silicon, 4 vCPUs, 4 GB) with `TC_SRC` on the VM's disk, 2026-10-04. Each
target takes about 20 minutes; all pass `cross-toolchain-test`:

| Target | ELF | Interpreter | Extra checks | Tarball (arm64 host) |
|--------|-----|-------------|--------------|----------------------|
| `arm64` | AArch64 | `/lib/ld-linux-aarch64.so.1` | — | 102 MB |
| `x86_64` | X86-64 | `/lib64/ld-linux-x86-64.so.2` | — | 105 MB |
| `armv6` | ARM | `/lib/ld-linux-armhf.so.3` | `Tag_CPU_arch: v6`, VFP args | 90 MB |
| `armv7` | ARM | `/lib/ld-linux-armhf.so.3` | `Tag_CPU_arch: v7`, VFP args | 89 MB |
| `riscv64` | RISC-V | `/lib/ld-linux-riscv64-lp64d.so.1` | RVC, double-float ABI | 115 MB |
| `i686` | Intel 80386 | `/lib/ld-linux.so.2` | no `__SSE2__` | 103 MB |
| `i686-sse2` | Intel 80386 | `/lib/ld-linux.so.2` | `__SSE2__`, `__SSE_MATH__` | 103 MB |

Unpacked prefixes are 250–380 MB each. An unpacked tarball works from any
directory (`-print-sysroot` resolves relative to the compiler). The binaries
are not run: the VMs are arm64 and x86_64 only.

Problems found and fixed on the way:

- the kernel's `headers_install` calls `rsync` (not in the dev image):
  replaced by `make headers` plus a tar copy, also for the native toolchain;
- glibc's configure picked up the host `g++` for its C++ test programs while
  gcc stage 1 has no C++: `CXX=<triplet>-g++`, which does not exist yet, so
  glibc skips them;
- `aarch64-linux-gnu` on an arm64 host canonicalised to the build triplet, so
  gcc configured itself as a native compiler: the build machine is now named
  `<arch>-build-linux-gnu`;
- glibc's library directories differ per target (`/usr/lib64` on aarch64)
  while gcc without multilib searches `lib`: glibc now always installs into
  `/lib` and `/usr/lib`, with `lib64 -> lib` links in each sysroot.
