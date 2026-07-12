# Super Minimal Linux Libre

Build a stripped-down GNU/Linux system from scratch using Linux-libre kernel, GNU coreutils, glibc, and GCC — no non-free firmware, minimal footprint, minimal attack surface.

**Target:** x86_64 (amd64), arm64 (aarch64) on QEMU/KVM with virtio drivers only.

**Build host:** Void Linux (aarch64)

---

## Git Submodules

All third-party sources are managed as git submodules under `sources/` — **never modified directly**.

```bash
# Initialize all submodules
git submodule update --init --recursive

# Add a new submodule
git submodule add <repo-url> sources/<name>

# Update a submodule to latest
git submodule update --remote sources/<name>
```

### Submodule URLs

| Package | Repository | Current Version | Notes |
|---------|-----------|-----------------|-------|
| linux-libre | `git://linux-libre.fsfla.org/releases.git` | `sources/v7.1.3-gnu` | deblobbed kernel |
| gcc | `https://gcc.gnu.org/git/gcc.git` | `basepoints/gcc-17-1907` | GNU C compiler |
| glibc | `https://sourceware.org/git/glibc.git` | `glibc-2.43` | GNU C library |
| binutils | `git://sourceware.org/git/binutils-gdb.git` | `binutils-2_46` | GNU binutils |
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
| runit | `https://github.com/g-pape/runit/` | `v2.3.1` | runit init |
| dhcpcd | `https://github.com/NetworkConfiguration/dhcpcd.git` | `v10.3.2` | DHCP client |

> All submodules use `--depth 1` (shallow clones). Note: gcc will be a full clone.

---

## File Structure

```
linux-vm/
│
├── Makefile                     main entry — includes mk/*.mk
├── mk/                          modular Makefile fragments
│   ├── 00-vars.mk              variables, directories, flags
│   ├── 01-setup.mk             phony targets, build-dirs, check-env
│   ├── 02-fake-bin.mk          stub scripts for missing host tools
│   ├── 03-source-prep.mk       copy + patch pipeline (sources → sources-patched)
│   ├── 04-build-rules.mk       per-package build rule macros (all 19 packages)
│   ├── 05-packages.mk          package declarations, aliases, install targets
│   ├── 06-toolchain.mk         cross-compiler (binutils → glibc → gcc)
│   ├── 07-kernel.mk            Linux-libre kernel (x86_64 + arm64)
│   ├── 08-clean-help.mk        clean, distclean, help
│   └── tee-log.sh              LOG=1 tee wrapper for per-target logs
│
├── sources/                     git submodules (NEVER modified)
│   ├── linux-libre/             Linux-libre kernel source
│   ├── gcc/                     GCC source
│   ├── glibc/                   glibc source
│   ├── binutils/                binutils source
│   ├── bash/                    GNU bash
│   ├── coreutils/               GNU coreutils
│   ├── grep/                    GNU grep
│   ├── sed/                     GNU sed
│   ├── gawk/                    GNU awk
│   ├── findutils/               GNU findutils
│   ├── diffutils/               GNU diffutils
│   ├── gzip/                    GNU gzip
│   ├── tar/                     GNU tar
│   ├── vim/                     vim editor
│   ├── iproute2/                iproute2 (network)
│   ├── procps-ng/               procps (ps, kill, ...)
│   ├── util-linux/              util-linux (mount, fdisk, ...)
│   ├── runit/                   runit init
│   └── dhcpcd/                  DHCP client
│
├── sources-patched/             patched source trees (gitignored)
│   └── <pkg>/                   one copy per package, patches applied once
│
├── sources-build/               per-arch build output (gitignored)
│   ├── x86_64/<pkg>/            x86_64 build directories
│   └── arm64/<pkg>/             arm64 build directories
│
├── sources-patches/             per-package patch files
│   ├── gzip/0001-rename-head-macro.patch
│   ├── tar/0001-remove-po.patch
│   ├── util-linux/0001-remove-po.patch
│   └── (other patches as needed)
│
├── build/                       shared build infrastructure (gitignored)
│   └── fake-bin/                stub scripts (autopoint, gperf, help2man, ...)
│
├── rootfs/                      staging root filesystems (gitignored)
│   ├── x86_64/                  x86_64 root
│   └── arm64/                   arm64 root
│
├── toolchain/                   cross-compiler install (gitignored)
│   ├── x86_64/bin/              x86_64 cross-tools
│   └── arm64/bin/               arm64 cross-tools
│
├── build-logs/                  per-target build logs (gitignored)
│   ├── build-coreutils-x86_64.log
│   ├── kernel-x86_64.log
│   └── ...
│
├── README.md                    this file
├── TODO.md                      detailed build plan
├── .gitignore
├── .gitmodules
├── kernel-x86_64.config         x86_64 kernel config (tinyconfig-based)
├── kernel-arm64.config          arm64 kernel config (tinyconfig-based)
│
├── minimal-libre.tar.gz         packaged rootfs (aspirational)
├── strip.sh                     post-build stripping script
└── qemu-test.sh                 QEMU launch script
```

---

## Build System

The Makefile (`Makefile`) orchestrates all builds. It's split into modular fragments under `mk/`.

### Build Pipeline

```
sources/<pkg>  ──copy+patch──→  sources-patched/<pkg>/  (once, idempotent stamp)
                                       │
                                ┌──────┴──────┐
                                ▼              ▼
                    sources-build/x86_64/   sources-build/arm64/
                    <pkg>/ (build output)    <pkg>/ (build output)
```

All 19 packages flow through this pipeline — **`sources/` is never modified**.

### Build Order

```
1. toolchain-x86_64  (binutils → linux-headers → glibc-headers → gcc-stage1 → glibc → gcc-final)
2. userland-x86_64   (all 15 packages, auto-depends on toolchain)
3. kernel-x86_64     (linux-libre, independent of userland)
```

Userland package targets automatically depend on `toolchain-<target>` (order-only prerequisite).

### Basic Usage

```bash
# Show all targets
make help

# Prepare patched sources (copy + patch, no build)
make prepare-sources                  # all packages
make prepare-sources-coreutils        # one package

# Build toolchain (cross-compiler)
make toolchain-x86_64                 # full 6-step toolchain for x86_64

# Build userland
make all                              # all userland for all targets
make coreutils                        # one package, all targets
make build-coreutils-x86_64           # one package, one target

# Build kernel
make kernel-x86_64                    # kernel for x86_64

# Install
make install                          # install everything to rootfs/
make install-x86_64                   # install x86_64 only

# Clean
make clean                            # remove build artifacts
make distclean                        # clean + remove rootfs + toolchain
```

### Logging

```bash
make build-coreutils-x86_64 LOG=1     # → build-logs/build-coreutils-x86_64.log
make all LOG=1                         # → build-logs/all.log
```

Each run overwrites the log (always the latest). For per-package sequential builds with timestamped logs, use `build-one-by-one.sh`.

### Build Methods Per Package

| Build Method | Packages |
|---|---|
| **GIT_GNULIB_RULES** (gnulib bootstrap + autoreconf) | coreutils, grep, sed, findutils, diffutils, gzip, tar |
| **GIT_AUTORECONF_RULES** (autoreconf, no gnulib) | procps-ng, util-linux |
| **GIT_CONFIGURE_RULES** (direct configure) | bash, gawk |
| **Custom** | vim, iproute2, runit, dhcpcd |
| **Toolchain** (6-step) | binutils, linux-headers, glibc, gcc |
| **In-tree build** | linux-libre (kernel) |

### Common Flags

```bash
make STRIP=0 install                  # skip binary stripping
make -j8 all                          # parallel build
make all LOG=1                        # log to build-logs/
```

### Patches

Patches live in `sources-patches/<pkg>/*.patch` and are applied once when copying from `sources/` to `sources-patched/<pkg>/`.

| Package | Patches | Reason |
|---------|---------|--------|
| gzip | `0001-rename-head-macro.patch` | Rename `head` macro → `gzip_head` (collides with aarch64 sigcontext.h) |
| tar | `0001-remove-po.patch` | Remove `po` from SUBDIRS (no gettext needed) |
| util-linux | `0001-remove-po.patch` | Remove `po` from SUBDIRS |

### Fake-bin Stubs

Host tools not available on the build host are stubbed via `build/fake-bin/`:

| Stub | Purpose |
|------|---------|
| `autopoint` | GNU gettext version reporter |
| `gperf` | GNU gperf (generates C from .gperf files) |
| `help2man` | Man page generator |
| `gtkdocize` | gtk-doc documentation tool |

### Known Build Issues & Fixes

| Package | Issue | Fix Applied |
|---------|-------|-------------|
| gzip | `head` macro collides with aarch64 `sigcontext.h` | Patch renames `head` → `gzip_head` |
| gzip/tar | Missing `gl_TYPE_WINT_T_PREREQ` and `AM_ICONV` m4 macros | Stubs added in GIT_GNULIB_RULES |
| tar | Missing `Make.rules` from `paxutils` submodule | Custom build rule initializes paxutils |
| vim | Configure wrapper expects `auto/configure` in src | Build rule copies src to build dir |
| iproute2 | Non-autoconf configure rejects `--disable-nls` | Custom build rule passes only supported flags |
| util-linux | `autoreconf` requires `gtkdocize` | Fake-bin stub added |
| runit | Default Makefile target builds tarball, not binaries | Custom build rule uses `package/compile` |
| dhcpcd | Non-autoconf configure needs to run in source tree | Custom build rule copies source to build dir |

### Packages Covered

- ✅ Toolchain: binutils, glibc, gcc
- ✅ Userland (15/15): coreutils, bash, grep, sed, gawk, findutils, diffutils, gzip, tar, vim, iproute2, procps-ng, util-linux, runit, dhcpcd
- ✅ Kernel: linux-libre (both x86_64 + arm64)

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

- Linux Libre: https://linux-libre.fsfla.org/
- Void Linux: https://voidlinux.org/
- Linux From Scratch: https://www.linuxfromscratch.org/
- runit: http://smarden.org/runit/
