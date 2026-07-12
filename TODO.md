# Super Minimal Linux Libre — Build Plan

**Status:** All 15 userland packages build cleanly for both x86_64 and arm64. Phases 1-3 complete.
**Next:** Phase 5 (Strip, minimize, harden).

**Goal:** Build a stripped-down GNU/Linux system using Linux-libre kernel, GNU coreutils, glibc, and GCC — no non-free firmware, minimal attack surface, minimal footprint.

**Target:** x86_64 + arm64 on QEMU/KVM with virtio drivers only.

---

## Build System Complete

The Makefile is modularized under `mk/`:

| File | Purpose |
|------|---------|
| `mk/00-vars.mk` | Variables, directories, flags, `LOG=1` logging |
| `mk/01-setup.mk` | `build-dirs`, `check-env` |
| `mk/02-fake-bin.mk` | Stub scripts for missing autotools |
| `mk/03-source-prep.mk` | Copy + patch pipeline (all 19 packages) |
| `mk/04-build-rules.mk` | Build rule macros for all packages |
| `mk/05-packages.mk` | Package declarations, aliases, install |
| `mk/06-toolchain.mk` | 6-step cross-compiler toolchain |
| `mk/07-kernel.mk` | Linux-libre kernel (x86_64 + arm64) |
| `mk/08-clean-help.mk` | Clean, distclean, help |
| `mk/tee-log.sh` | `LOG=1` shell wrapper for per-target logs |

**Pipeline:** `sources/` → `sources-patched/` (copy + patches, once) → `sources-build/<arch>/` (build output)

**Key design rules:**
- `sources/` is NEVER modified — all copies go through `sources-patched/`
- `.patched` stamp files make source preparation idempotent
- Userland packages auto-depend on toolchain via `| toolchain-<arch>`
- `LOG=1` tees all output to `build-logs/<target>.log`

---

## Current State

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Foundations — project structure, Makefile, patches | ✅ Complete |
| 1 | Linux-libre kernel | ✅ Complete |
| 2 | GCC + glibc + binutils toolchain | ✅ Make targets ready |
| **3** | **Minimal GNU userland** | **✅ 15/15 packages building — all issues fixed** |
| 4 | Init system + `/etc` skeleton | ✅ Completed |
| 5 | Strip, minimize, harden | ⏳ Not started |
| 5.5 | MBR disk image + bootloader | ⏳ Not started |
| 6 | QEMU verification + packaging | ⏳ Not started |
| 7 | Hardening (seccomp, sysctl) | ⏳ Not started |

### Package Build Status

| # | Package | Build System | x86_64 | arm64 | Notes |
|---|---------|-------------|--------|-------|-------|
| 6 | coreutils | gnulib bootstrap | ✅ | ✅ aarch64 | |
| 7 | bash | direct configure | ✅ | ✅ aarch64 | |
| 8 | grep | gnulib bootstrap | ✅ | ✅ aarch64 | |
| 9 | sed | gnulib bootstrap | ✅ | ✅ aarch64 | |
| 10 | gawk | direct configure | ✅ | ✅ aarch64 | |
| 11 | findutils | gnulib bootstrap | ✅ | ✅ aarch64 | |
| 12 | diffutils | gnulib bootstrap | ✅ | ✅ aarch64 | |
| 13 | gzip | gnulib bootstrap | ✅ | ✅ aarch64 | Patch: `head` → `gzip_head` |
| 14 | tar | gnulib bootstrap | ✅ | ✅ aarch64 | |
| 15 | vim | custom | ✅ | ✅ aarch64 | arm64 uses termcap stub (`sources-patches/vim/termcap-stub.c`), x86_64 uses system ncurses |
| 16 | iproute2 | custom configure | ✅ | ✅ aarch64 | |
| 17 | procps-ng | autoreconf | ✅ | ✅ aarch64 | arm64 built with `--without-ncurses` (slabtop/hugetop/top/watch excluded) |
| 18 | util-linux | autoreconf | ✅ | ✅ aarch64 | |
| 19 | runit | custom (package/compile) | ✅ | ✅ aarch64 | runit binary is statically linked |
| 20 | dhcpcd | custom configure | ✅ | ✅ aarch64 | |
| 21 | linux-libre (x86_64) | in-tree | ✅ | — | 2.3 MB bzImage |
| 22 | linux-libre (arm64) | in-tree | — | ✅ | 2.4 MB Image.gz |

---

## Phase 4 — Init System (✅)

- [x] All binaries consolidated to `/bin` only (no `/usr/bin`, `/usr/sbin`, `/sbin` except `/sbin/init` symlink)
- [x] `/sbin/init` → `/bin/runit-init` symlink for kernel
- [x] Fixed runit install: all 9 programs (runit, runit-init, runsv, runsvdir, runsvchdir, chpst, sv, svlogd, utmpset)
- [x] `/etc/runit/1` — one-time system init (mounts proc, sysfs, devtmpfs, devpts, tmpfs, sets hostname, loopback)
- [x] `/etc/runit/2` — runsvdir supervisor on `/etc/service/`
- [x] `/etc/runit/3` — graceful shutdown (stop services, umount, poweroff/reboot)
- [x] `/etc/runit/ctrlaltdel` — Ctrl+Alt+Del handler
- [x] `/etc/fstab` — proc, sysfs, devtmpfs, devpts, tmpfs
- [x] `/etc/passwd` — root + standard system users (all `/bin` shell paths)
- [x] `/etc/group` — standard groups
- [x] `/etc/shadow` — empty root password
- [x] `/etc/hostname` — `linux-libre`
- [x] `/etc/hosts` — localhost + loopback entries
- [x] `/etc/resolv.conf` — Cloudflare + Google DNS
- [x] Getty service on serial console (ttyS0 for x86_64, ttyAMA0 for arm64)
- [x] devtmpfs for `/dev` (no static device nodes needed)

---

## Phase 5 — Strip & Minimize (⏳)

- [ ] Strip binaries: `make strip-all` (built into `make install`)
- [ ] Remove docs/locale: `make prune-docs` (built into `make install`)
- [ ] Remove unused programs from coreutils

---

## Phase 5.5 — Disk Image (⏳)

- [ ] Create raw disk image: `dd if=/dev/zero of=disk.img bs=1M count=256`
- [ ] Partition with MBR (sfdisk)
- [ ] Format ext4, copy rootfs
- [ ] Install bootloader (GRUB or custom bootsector)
- [ ] Test with QEMU

---

## Phase 6 — Verification (⏳)

### QEMU Boot Test

- [ ] Boot kernel with initramfs via QEMU:
      ```
      qemu-system-x86_64 -kernel path/to/bzImage -initrd path/to/initramfs -nographic -append "console=ttyS0"
      ```
- [ ] Parse serial console stdout and confirm:
      - Kernel boots without panics
      - **runit** (or init script) starts and spawns a shell
      - `agetty` or shell presents a **root prompt** (`/ #` or `root@host:~#`)
      - System is responsive to keyboard input
- [ ] Verify filesystem mounts correctly (proc, sysfs, devtmpfs)
- [ ] Test basic commands: `ls`, `ps`, `cat /proc/version`
- [ ] Shutdown gracefully

### Metrics

- [ ] Measure sizes (kernel < 5 MB, rootfs < 100 MB)
- [ ] Measure RAM usage (< 64 MB idle)
- [ ] Verify no non-free firmware loaded (`dmesg | grep -i firmware`)
- [ ] Count running processes (< 15)
- [ ] Package: `tar -cvzf minimal-libre.tar.gz rootfs`

---

## Phase 7 — Hardening (⏳)

- [ ] Sysctl hardening
- [ ] seccomp filter
- [ ] Remove setuid binaries
- [ ] Review `/proc` permissions

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
