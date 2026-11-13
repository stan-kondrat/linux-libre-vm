#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Print the notes of a GitHub release (Markdown), for build-release.yml.
#
# Usage: scripts/release-notes.sh NAME BASE_DIR
#   NAME      release tag (v0.3.2, ...) or "edge"
#   BASE_DIR  directory with the base release files (reads MANIFEST-x86_64.txt)
#
# Environment: GITHUB_REPOSITORY (owner/repo), GITHUB_SHA (commit)
# ═════════════════════════════════════════════════════════════════════════════

set -eu

T=$1
BASE=$2
REPO=${GITHUB_REPOSITORY:-stan-kondrat/linux-libre-vm}
SHA=${GITHUB_SHA:-$(git rev-parse HEAD)}

if [ "$T" = edge ]; then
	cat <<EOF
## Edge build: main at \`$(printf %.12s "$SHA")\`

Built and tested from the newest commit on \`main\`. It is replaced on every
push to \`main\` and is not a release: the VM scripts use it only with
\`VM_RELEASE=edge\`.

EOF
	REF=$SHA
else
	cat <<EOF
## Super Minimal Linux Libre ${T}

EOF
	REF=$T
fi

cat <<EOF
Minimal GNU/Linux system: Linux-libre kernel, GNU userland, glibc, runit.
Both images boot straight to a root shell on the serial console,
configure \`eth0\` by DHCP and run an OpenSSH server (root, key login only).

### Run it

With this repository (UTM on Apple Silicon, or QEMU anywhere): the VM
scripts download the newest release by default (\`VM_RELEASE=${T}\` for this one).

\`\`\`bash
make utm-create utm-start utm-console        # macOS + UTM, arm64
make qemu-start qemu-console                 # QEMU, arm64 (QEMU_ARCH=x86_64 for the other)
\`\`\`

With plain QEMU (\`unxz\` the images first, or use the uncompressed ones):

\`\`\`bash
# x86_64 (q35, virtio-pci)
qemu-system-x86_64 -M q35 -m 256 -nographic -nodefaults -serial mon:stdio \\
  -kernel linux-libre-vmlinuz-x86_64 -append "root=/dev/vda rw console=ttyS0" \\
  -drive file=linux-libre-vm-x86_64.img,format=raw,if=none,id=drive0 \\
  -device virtio-blk-pci,drive=drive0 \\
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0

# arm64 (virt, virtio-mmio: the kernel has no PCI)
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 256 -nographic -nodefaults -serial mon:stdio \\
  -kernel linux-libre-vmlinuz-arm64 -append "root=/dev/vda rw console=ttyAMA0" \\
  -drive file=linux-libre-vm-arm64.img,format=raw,if=none,id=drive0 \\
  -device virtio-blk-device,drive=drive0 \\
  -netdev user,id=net0 -device virtio-net-device,netdev=net0
\`\`\`

Add \`-accel kvm -cpu host\` (Linux, same architecture) or \`-accel hvf -cpu host\`
(macOS, arm64) for hardware acceleration. Quit with Ctrl-a x.

SSH: the images contain no keys and no passwords. Add your public key to
\`/root/.ssh/authorized_keys\` on the serial console, forward a port
(\`-netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22\`, or \`SSH_PORT=2222\`
with the VM scripts), then \`ssh -p 2222 root@127.0.0.1\`.

### Assets

| File | Description |
|------|-------------|
| \`linux-libre-vm-{x86_64,arm64}.img.xz\` | root filesystem: raw ext4, no partition table (xz) |
| \`linux-libre-vm-{x86_64,arm64}.img\` | the same, uncompressed |
| \`linux-libre-vmlinuz-{x86_64,arm64}\` | kernel (x86_64 bzImage, arm64 Image.gz), booted directly |
| \`linux-libre-{x86_64,arm64}.config\` | kernel configuration |
| \`linux-libre-{x86_64,arm64}.System.map\` | kernel symbol map (for debugging) |
| \`MANIFEST-{x86_64,arm64}.txt\` | upstream versions, toolchain, host libraries, file list |
| \`linux-libre-vm-src-${T}.tar.xz\` | complete corresponding source: all upstream sources, patches and build system |
| \`SHA256SUMS\` | checksums of the files above |

glibc, libgcc and the other runtime libraries are copied from the Ubuntu
24.04 build host; \`MANIFEST-*.txt\` lists their Ubuntu packages and
versions, whose source is available from Ubuntu.

### Dev images

The base image plus a toolchain built from pinned sources (gcc, binutils,
glibc, make, perl, Python, Node.js) and cross compilers for seven targets
under \`/opt/cross\`. See
[docs/ci-dev.md](https://github.com/${REPO}/blob/${REF}/docs/ci-dev.md).

| File | Content |
|------|---------|
| \`linux-libre-vm-dev-<arch>.img.xz\` | dev disk image (8 GB when unpacked; \`.partNN\` pieces: \`cat\` them together) |
| \`linux-libre-vmlinuz-dev-<arch>\` | kernel to boot it |
| \`cross-<triplet>.<host arch>.tar.gz\` | each cross toolchain on its own, relocatable |
| \`MANIFEST-dev-<arch>.txt\` | source commits, build host, sizes |
| \`linux-libre-vm-dev-src-${T}.tar.xz\` | corresponding source |
| \`SHA256SUMS-dev\` | checksums of the dev files |

### Upstream versions

\`\`\`
$(sed -n '/^## Upstream sources/,/^$/p' "$BASE/MANIFEST-x86_64.txt" | sed '1d;$d')
\`\`\`
EOF
