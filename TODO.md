# Super Minimal Linux Libre — Build Plan

**Status:** Both x86_64 and arm64 boot to login prompt ✅
**Next:** QEMU verification (login, basic commands, networking, measurements).

---

## Build System

| File | Purpose |
|------|---------|
| `mk/00-vars.mk` | Variables, directories, flags |
| `mk/01-setup.mk` | `build-dirs`, `check-env` |
| `mk/02-fake-bin.mk` | Stub scripts for missing autotools |
| `mk/03-source-prep.mk` | Copy + patch pipeline |
| `mk/04-build-rules.mk` | Build rule macros for all packages |
| `mk/05-packages.mk` | Package declarations, install, consolidate-bin, install-libs |
| `mk/07-kernel.mk` | Linux-libre kernel (x86_64 + arm64) |
| `mk/08-clean-help.mk` | Clean, distclean, help |
| `mk/09-init.mk` | Init system + /etc skeleton |
| `mk/10-disk.mk` | Disk image creation + QEMU targets |

---

## Current State

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Foundations | ✅ Complete |
| 1 | Linux-libre kernel | ✅ Compiled (x86_64: 4.0M, arm64: 2.8M) |
| 2 | Toolchain | ✅ Host-provided |
| 3 | Minimal GNU userland | ✅ 15/15 packages built |
| 4 | Init system + /etc skeleton | ✅ Completed |
| 5 | Strip & minimize | ⏳ Not started |
| 5.5 | Disk image + QEMU boot | ✅ Complete |
| 6 | QEMU verification | ⏳ In progress |
| 7 | Hardening | ⏳ Not started |

---

## Phase 4 — Init & Consolidation (✅)

- [x] All binaries in `/bin` only — `/usr/bin`, `/usr/sbin`, `/sbin` stripped
- [x] `/sbin/init → /bin/runit-init` symlink
- [x] `/sbin/runit → /bin/runit` symlink (runit-init hardcodes `/sbin/runit`)
- [x] `/bin/sh → /bin/bash` symlink (scripts use `#!/bin/sh`)
- [x] runit: all 9 programs installed to `/bin`
- [x] `/etc/runit/{1,2,3,ctrlaltdel}` — stage scripts
- [x] `/etc/fstab`, `/etc/passwd`, `/etc/group`, `/etc/shadow`
- [x] `/etc/hostname`, `/etc/hosts` (no IPv6), `/etc/resolv.conf`
- [x] Getty on serial console (ttyS0 / ttyAMA0)

---

## Phase 5.5 — Disk Image (✅)

- [x] `mk/10-disk.mk` with `disk-image-<arch>` + `qemu-<arch>` targets
- [x] Raw ext4 image via `mke2fs -d` — no root required
- [x] Kernel feature fix: disabled `metadata_csum`, `orphan_file`, `flex_bg`, `huge_file`, `dir_nlink`
- [x] Shared library copying (`install-libs-<arch>`): sysroot-aware for cross-compilation
- [x] `ld-linux` library path: `/usr/lib64 → /lib` symlink so dynamic linker finds libs
- [x] `hostname` replaced with direct `/proc/sys/kernel/hostname` write (removed from coreutils)
- [x] Stage 2: `sleep 1` + stderr redirect to suppress transient runsv noise
- [x] arm64: `-cpu cortex-a57` (default QEMU CPU doesn't support AArch64)
- [x] arm64: `CONFIG_PCI_HOST_GENERIC=y` (no virtio-blk without it)
- [x] arm64: `/sbin/runit` + `/bin/sh` symlinks (consolidate-bin wasn't run)
- [x] QEMU boots kernel → runs `/sbin/init` → runit starts → stage scripts clean → login prompt (both arches)

---

## Phase 6 — Verification (⏳)

- [x] Boot to login prompt (both x86_64 + arm64)
- [x] proc, sysfs, devtmpfs mounted (stage 1)
- [x] Getty on serial console (ttyS0 / ttyAMA0)
- [x] Login as root (empty password)
- [x] `ps` works — processes visible ✅
- [x] `whoami`, `pwd`, `ls` work ✅
- [x] Loopback networking (127.0.0.1) ✅
- [x] DHCP via QEMU slirp: x86_64 gets 10.0.2.15 ✅, arm64 times out ⏳
- [x] Memory: ~21MB used at idle (x86_64), ~14MB (arm64) ✅
- [x] `make test-dhcpcd` target added
- [x] `make test-shutdown` target added (stage 3 uses `kill -TERM 1`)
- [ ] Measure disk image sizes post-stripping

---

## Phase 7 — Hardening (⏳)

- [ ] seccomp filter
- [ ] Remove setuid binaries
- [ ] Review /proc permissions

---

## Targets

| Metric | Target | Current |
|--------|--------|---------|
| Kernel image | < 3 MB | x86_64: 4.0M, arm64: 2.8M (arm64 ✅) |
| Rootfs (uncompressed) | < 50 MB | x86_64: ~82M, arm64: ~71M (with libs) |
| RAM at idle | < 64 MB | ? |
| Running processes | < 10 | ? |
| Non-free blobs | 0 | 0 ✅ |
