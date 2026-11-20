# Dev image in CI

`.github/workflows/build-dev.yml` builds the dev images and cross toolchains
for both hosts on GitHub runners. It is a reusable workflow: the
`Build & Release` workflow (`build-release.yml`) runs it next to the base
images (`build-base.yml`) and publishes both in one release.

The dev image ([self-hosting.md](self-hosting.md)) and the cross toolchains
([cross-toolchains.md](cross-toolchains.md)) are build-once artifacts, like the
base image: built from pinned sources, published as release assets and then
used as they are. Nothing is rebuilt inside a VM.

## Why its own workflow file, split into jobs

- The toolchain targets build for the host's own architecture only
  (`TC_ARCH`), so each dev image needs a runner of its architecture:
  `ubuntu-24.04` for x86_64, `ubuntu-24.04-arm` for arm64.
- The whole build (native toolchain, Node, seven cross toolchains) takes
  longer than GitHub's 6-hour job limit. The cross toolchains are
  independent of the native one and run as jobs of their own, in parallel.
  The native toolchain (`make toolchain`, Node included) is one job that
  can be resumed (below).
- Its stages change rarely (build once): on most pushes every stage is
  cached and only `base` and `assemble` do work.

## When it runs

`build-release.yml` calls it on every push to `main` and on release tags
(`v*`, `release-*`), not on pull requests. Each commit is built once:

| Event | Builds | Publishes |
|-------|--------|-----------|
| pull request | base images only | nothing |
| push to `main` | base + dev | the `edge` pre-release: base and dev files of that commit, replaced on every push |
| tag | nothing, when `main` built the commit successfully; base + dev otherwise | the tag's release: base and dev files together |

A tag run starts with the `find` job: it looks for the successful
`Build & Release` run of the same commit on `main` and, if one still has all
its artifacts (kept 30 days), the `publish` job takes the files from that run.
A `main` run of the commit that is still going is waited for (up to 5 h 40 min;
after that the job fails and the tag run is re-run once `main` is done). Only
a commit that `main` never built successfully is built in the tag run.

`main` runs queue instead of cancelling each other, and a newer push replaces
a run that is still waiting, so `edge` follows the newest commit.

## Jobs (per host: x86_64, arm64)

| Job | Make targets | Needs | x86_64 | arm64 |
|-----|--------------|-------|--------|-------|
| `base` | `userland-<arch>`, `kernel` (native) | — | 13 min | 16 min |
| `toolchain` | `toolchain`: Linux headers, glibc, binutils, gcc, make, m4, bison, flex, bc, perl, zlib, bzip2, python, node | — | 133 min | 166 min |
| `cross` (×7 targets) | `cross-toolchain`, `cross-toolchain-test`, `cross-toolchain-dist` `TARGET=<t>` | — | 35–61 min each | 33–49 min each |
| `assemble` | `install-dev`, `disk-image-dev`, smoke test | all of the above | 16 min | 12 min |
| `sources` | toolchain source tarball (runs once) | — | 28 min | |

Times are job durations on GitHub-hosted runners (`ubuntu-24.04`,
`ubuntu-24.04-arm`), measured in the `main` run of commit `dd55eba`. The jobs
run in parallel, so a run lasts about as long as `toolchain`; with cold caches
the dev run of the `v0.3.0` tag took 3 h 15 min. The base images' own jobs
(`build-base.yml`) take 15 min to build and 24 min for the source tarball.

A small `keys` job computes the cache keys first. `base`, `toolchain` and
the 14 `cross` jobs all run in parallel, and a `sources` job packs the
toolchain sources. The dev files are artifacts of the run; publishing them is
`build-release.yml`'s `publish` job.

Host tools are fine for building: the toolchain's programs are built with the
runner's gcc. What goes into the image comes from the pinned sources.

### Resuming the toolchain job

The toolchain job runs `make toolchain` under `timeout` (5 h 25 min) and,
whether it finished or not, saves its stages under a unique cache key
(`dev-toolchain-<arch>-<inputs>-<run id>-<attempt>`). It restores by the
prefix, so it starts from the newest saved state: the stamps of finished
stages make `make` skip them. A job that ran out of time fails; "Re-run
failed jobs" continues where it stopped (a stage cut off in the middle,
without its stamp, starts again). `assemble` restores the same way and then
checks with `make -q toolchain-stamps` that every stage is there.

## Stage caches

Every build job caches its output under a key made from exactly the inputs
of that stage, and skips the build on a hit. A job restores the caches of
the stages it needs; `assemble` restores all of them, so no stage output is
passed as an artifact and stored twice.

| Stage | Cached paths (under `TOOLCHAIN_WORK`) | Key inputs |
|-------|---------------------------------------|------------|
| `base` | `sources-patched`, `sources-build/<arch>` (repo) | base submodule SHAs, patches, templates, `mk/0*.mk`, `mk/*.sh`, kernel configs |
| `toolchain` | `stamps/`, `root/`, `deps/`, `pybin/` | SHAs of `binutils gcc glibc bc perl python node linux-libre`, `scripts/fetch-toolchain.sh` (tarball pins), `mk/14-toolchain.mk` |
| `cross-<t>` | `cross/<t>/` | SHAs of `binutils gcc glibc linux-libre`, `mk/14-toolchain.mk`, `mk/15-cross-toolchain.mk`, target name |

Only installed output and stamp files are cached, never the build trees.
Restored stamps keep their times (the cache is a tar), so `make` sees every
cached stage as done. `assemble` checks every toolchain stamp with `make -q`
before building, so a cache that does not match fails the job instead of
starting a rebuild.

`TOOLCHAIN_WORK` is the same fixed path in every job: `pybin/` holds absolute
links into `root/`, and the stamps and cross prefixes are tied to their paths.
Before building, each job removes preinstalled SDKs from the runner to make
room on its disk.

### Cache limits

- GitHub keeps up to 10 GB of caches per repository and evicts entries not
  used for 7 days. Estimated per host: `toolchain` ~0.7 GB (plus older
  partial saves until they are evicted), cross ~0.8 GB; with `base` about
  3–4 GB for both hosts, next to the caches of `build-base.yml`.
- A run can restore caches of its own ref and of the default branch. `main`
  builds every commit, so its caches are the ones that stay warm; a tag of a
  built commit restores no cache at all (it publishes `main`'s artifacts).
- Caches are a speedup only. The release assets are what is kept.

## Smoke test

`assemble` boots the dev image with `scripts/smoke-test.sh PROFILE=dev` (the
same script as `make test-dev` and the base workflow's boot test): serial
console, DHCP, ssh login with a throwaway key and ssh password login as a
test user (SHA-512 hash), then over ssh compiling and running a C and a C++
program, one cross compiler per target (`<triplet>-gcc -c`), `make`, `python3 -c 'import zlib, bz2'` and `node -e`. The run fails,
and nothing is published, if any check fails. QEMU uses KVM when the runner
offers it, TCG otherwise (slow but enough for these commands).

Shared steps (disk cleanup, packages, QEMU with KVM) are the composite action
`.github/actions/setup-host`, used by both build workflows.

## Container image

The dev root filesystem is also published as a container image, so a job of
another project can build inside it:

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04            # ubuntu-24.04-arm for arm64
    container: ghcr.io/stan-kondrat/linux-libre-vm-dev:v0.4.0
    steps:
      - uses: actions/checkout@v4
      - run: gcc --version && /opt/cross/aarch64-linux-gnu/bin/aarch64-linux-gnu-gcc --version
```

| Image | Content |
|-------|---------|
| `ghcr.io/stan-kondrat/linux-libre-vm-dev:<tag>` | multi-arch: `linux/arm64` and `linux/amd64`; `<tag>` is the release tag (`v0.4.0`), or `edge` for the newest `main` build |
| `ghcr.io/stan-kondrat/linux-libre-vm-dev:<tag>-arm64`, `-x86_64` | one architecture |

It is exactly the root filesystem of `linux-libre-vm-dev-<arch>.img.xz` (same
userland, same glibc, `/opt/cross/*`, Python, Node.js), one layer, imported
with `docker import` and no Dockerfile. Only the kernel differs: a container
runs on the runner's kernel, not linux-libre, so builds must not depend on
`uname`. The container starts as root; any uid works for compiling.

Labels: `org.opencontainers.image.version` (release tag),
`org.opencontainers.image.revision` (commit), `org.opencontainers.image.source`,
and `io.github.stan-kondrat.linux-libre-vm.img-xz-sha256`, the checksum of the
`.img.xz` made from the same rootfs.

### Release identity

The disk image and the container carry the same files, written by
`make install-dev-release` (`mk/16-dev-release.mk`, `scripts/dev-release.sh`):

| File | Content |
|------|---------|
| `/usr/share/linux-libre-vm/release` | release tag, or `edge` |
| `/usr/share/linux-libre-vm/commit` | commit of this repository |
| `/usr/share/linux-libre-vm/MANIFEST-dev-<arch>.txt` | the release's manifest of the same name |
| `/etc/os-release` | `VERSION_ID` = tag, `BUILD_ID` = commit |

A tag publishes the build of the `main` run of its commit, made before the tag
existed, whose `release` says `edge`. So on a tag run the `retag` job writes the
tag into the disk image (`release` and `/etc/os-release`; the commit stays) with
`scripts/retag-image.sh`, and the release's `.img.xz` is that image, packed
again. The container import does the same to the rootfs it imports. Both say the
tag; a build made in the tag run itself already does, and passes through
unchanged. The `.img.xz` of a tag therefore differs from the `edge` one of the
same commit in these two files, and the label with its checksum is the checksum
of the release's file.

### How it is published

`assemble` uploads, next to `dev-<arch>`, the artifact `rootfs-<arch>`: the
rootfs tarball the disk image was made from, and the sha256 of the `.img.xz`.
The jobs of `build-release.yml` use these artifacts, from the same run as the
release files (including a `main` run chosen by `find`; the `find` job requires
`rootfs-<arch>`, so a tag only promotes complete builds). On a tag, `retag` runs
first, once per architecture on an `ubuntu-24.04` runner: it unpacks the
`.img.xz`, loop-mounts it (sudo), writes the tag, packs it again (split into
pieces over 2 GB) and uploads `tagged-img-<arch>` and `tagged-sha-<arch>` to
this run. `publish` replaces the build's dev images with `tagged-img-*` before
it writes `SHA256SUMS-dev`, and `container` takes the label checksum from
`tagged-sha-<arch>`. Then:

1. `container` (per host, on a runner of its architecture): `docker import`
   (`scripts/container-import.sh`), `scripts/container-test.sh` as root and as
   uid 1000 inside the image, then push `<tag>-<arch>`.
2. `container-test` (per host): the pushed image as a job container,
   `actions/checkout` and `scripts/container-test.sh` inside it. `gcc` and every
   `/opt/cross/*/bin/*-gcc` compile and link hello world.
3. `container-manifest`: `docker buildx imagetools create` joins both into `<tag>`.

It runs on `main` (tag `edge`) and on tags. Nothing is published from pull requests.

### Setup on GitHub

The workflow pushes with `GITHUB_TOKEN` (`packages: write`). The first push
creates the package and links it to the repository through the
`org.opencontainers.image.source` label. Two things are done once in the web UI,
as the package owner:

- Package `linux-libre-vm-dev` → Package settings → Change visibility → Public
  (new packages are private; other projects' jobs pull without credentials).
- Same page, "Manage Actions access": the repository `linux-libre-vm` has Write
  access (added automatically when the package is created by this
  repository's workflow).

### Releases from before the container

`.github/workflows/backfill-container.yml` (Run workflow, input `tag`)
publishes the container of an existing release from its `.img.xz`: it checks the
file against `SHA256SUMS-dev`, mounts it, imports the root filesystem and adds
the identity files, which those images do not have, with the manifest of the
release. It tests and pushes like `container` and joins the architectures.

## Release assets

The `publish` job of `build-release.yml` creates the release (`edge` or the
tag) with the base and the dev files at once, and one set of notes for both.
SHA256SUMS lists the base files, `SHA256SUMS-dev` the dev files. The dev files:

| File | Content |
|------|---------|
| `linux-libre-vm-dev-<arch>.img.xz` | dev disk image (8 GB sparse, mostly empty, so it compresses well: 678 MB arm64, 727 MB x86_64); split into `.partNN` pieces if over 2 GiB |
| `linux-libre-vmlinuz-dev-<arch>` | kernel to boot it with (built in `base`) |
| `cross-<triplet>.<host arch>.tar.gz` | each cross toolchain on its own (14 files, 101–139 MB each) |
| `MANIFEST-dev-<arch>.txt` | source commits, runner image, cross `BUILD-INFO`, sizes |
| `linux-libre-vm-dev-src-<tag>.tar.xz` | corresponding source: toolchain submodules, pinned tarballs, linux-libre, build files (476 MB) |
| `SHA256SUMS-dev` | checksums of the dev files (`SHA256SUMS` is the base files') |

The dev files have names of their own (`-dev-`, `cross-`), so `vm/release.sh`
still finds the base image in the same release.
