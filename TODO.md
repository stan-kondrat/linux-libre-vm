# Super Minimal Linux Libre — Build Plan

**Status:** Userland ✅, init ✅, kernel compiled ✅ (x86_64: 4.0M, arm64: 2.8M).
**Next:** `make kernel` to compile linux-libre for both architectures.

**Goal:** Build a stripped-down GNU/Linux system using Linux-libre kernel, GNU coreutils, glibc, and GCC — no non-free firmware, minimal attack surface, minimal footprint.

**Target:** x86_64 + arm64 on QEMU/KVM with virtio drivers only.

---

## Build System

The Makefile is modularized under `mk/`:

| File | Purpose |
|------|---------|
| `mk/00-vars.mk` | Variables, directories, flags, `LOG=1` logging |
| `mk/01-setup.mk` | `build-dirs`, `check-env` |
| `mk/02-fake-bin.mk` | Stub scripts for missing autotools |
| `mk/03-source-prep.mk` | Copy + patch pipeline (all 19 packages) |
| `mk/04-build-rules.mk` | Build rule macros for all packages |
| `mk/05-packages.mk` | Package declarations, aliases, install, consolidate-bin |
| `mk/07-kernel.mk` | Linux-libre kernel (x86_64 + arm64) |
| `mk/08-clean-help.mk` | Clean, distclean, help |
| `mk/09-init.mk` | Init system + /etc skeleton |

**Pipeline:** `sources/` → `sources-patched/` (copy + patches, once) → `sources-build/<arch>/` (build output)

**Key design rules:**
- `sources/` is NEVER modified — all copies go through `sources-patched/`
- `.patched` stamp files make source preparation idempotent
- All binaries go to `/bin` only (post-install consolidation)
- Kernel configs tracked in git: `kernel-<arch>.config`
- Init files tracked in git: `templates/`

---

## Current State

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Foundations — project structure, Makefile, patches | ✅ Complete |
| 1 | Linux-libre kernel | ⏳ Config ready, not compiled yet |
| 2 | GCC + glibc + binutils toolchain | ✅ Make targets ready |
| 3 | Minimal GNU userland | ✅ 15/15 packages built |
| 4 | Init system + /etc skeleton | ✅ Completed |
| 5 | Strip, minimize, harden | ⏳ Not started |
| 5.5 | Disk image + QEMU boot | ✅ Done (rootless via mke2fs -d) |
| 6 | QEMU verification + packaging | ⏳ Not started |
| 7 | Hardening (seccomp, sysctl) | ⏳ Not started |

---

## Phase 4 — Init System (✅)

- [x] All binaries consolidated to `/bin` only
- [x] `/sbin/init` → `/bin/runit-init` symlink
- [x] runit: all 9 programs installed to `/bin`
- [x] `/etc/runit/{1,2,3,ctrlaltdel}` — stage scripts
- [x] `/etc/fstab`, `/etc/passwd`, `/etc/group`, `/etc/shadow`
- [x] `/etc/hostname`, `/etc/hosts` (no IPv6), `/etc/resolv.conf`
- [x] Getty on serial console (ttyS0 / ttyAMA0)
- [x] Templates in `templates/` directory (tracked in git)

---

## Phase 5 — Strip & Minimize (⏳)

- [ ] Remove unused programs from coreutils
- [ ] Strip bash loadable builtins
- [ ] Strip static libs / headers / dev files
- [ ] Further vim pruning

---

## Phase 5.5 — Disk Image (⏳)

- [x] `mk/10-disk.mk` with `disk-image-<arch>` targets
- [x] Raw ext4 image via `mke2fs -d` — no root, no loop devices
- [x] No bootloader needed — QEMU boots with `-kernel bzImage -append "root=/dev/vda"`
- [ ] Test with QEMU

---

## Phase 6 — Verification (⏳)

- [ ] Boot kernel with initramfs via QEMU
- [ ] Verify runit spawns shell
- [ ] Test basic commands
- [ ] Measure sizes, RAM, processes

---

## Phase 7 — Hardening (⏳)

- [ ] seccomp filter
- [ ] Remove setuid binaries
- [ ] Review /proc permissions

---

## Targets

| Metric | Target |
|--------|--------|
| Kernel image | < 3 MB |
| Rootfs (uncompressed) | < 50 MB |
| Rootfs (compressed) | < 15 MB |
| RAM at idle | < 64 MB |
| Running processes | < 10 |
| Non-free blobs | 0 |
