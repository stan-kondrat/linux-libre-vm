# Dev image in CI

`.github/workflows/build-dev.yml` builds the dev images and cross toolchains
for both hosts on GitHub runners and publishes them.

The dev image ([self-hosting.md](self-hosting.md)) and the cross toolchains
([cross-toolchains.md](cross-toolchains.md)) are build-once artifacts, like the
base image: built from pinned sources, published as release assets and then
used as they are. Nothing is rebuilt inside a VM.

## Why a separate workflow, split into jobs

- The toolchain targets build for the host's own architecture only
  (`TC_ARCH`), so each dev image needs a runner of its architecture:
  `ubuntu-24.04` for x86_64, `ubuntu-24.04-arm` for arm64.
- The whole build (native toolchain, Node, seven cross toolchains) takes
  longer than GitHub's 6-hour job limit. The cross toolchains are
  independent of the native one and run as jobs of their own, in parallel.
  The native toolchain (`make toolchain`, Node included) is one job that
  can be resumed (below).
- It runs rarely (build once), so it does not belong in `build-release.yml`,
  which runs on every push.

Triggers: `workflow_dispatch`, and the release tags of `build-release.yml`
(`v*`, `release-*`): pushing one tag gives one release with both the base and
the dev files (below).

## Jobs (per host: x86_64, arm64)

| Job | Make targets | Needs | Estimate |
|-----|--------------|-------|----------|
| `base` | `userland-<arch>`, `kernel` (native) | — | 30–45 min |
| `toolchain` | `toolchain`: Linux headers, glibc, binutils, gcc, make, m4, bison, flex, bc, perl, zlib, bzip2, python, node | — | 3–6 h (Node 2–4 h) |
| `cross` (×7 targets) | `cross-toolchain`, `cross-toolchain-test`, `cross-toolchain-dist` `TARGET=<t>` | — | ~20 min each |
| `assemble` | `install-dev`, `disk-image-dev`, smoke test | all of the above | ~20 min |

A small `keys` job computes the cache keys first. `base`, `toolchain` and
the 14 `cross` jobs all run in parallel; then, on a release tag, `release`
adds both hosts' dev files to that tag's release.

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
  3–4 GB for both hosts, next to the caches of `build-release.yml`.
- A run can restore caches of its own ref and of the default branch. Run
  the workflow on `main` first (`workflow_dispatch`), then push the release
  tag: the tag run finds every stage cached and only assembles and uploads.
  Without that, the tag run builds everything (several hours) before the
  dev files appear on the release.
- Caches are a speedup only. The release assets are what is kept.

## Smoke test

`assemble` boots the dev image with `scripts/smoke-test.sh PROFILE=dev` (the
same script as `make test-dev` and the base workflow's boot test): serial
console, DHCP and ssh login with a throwaway key, then over ssh compiling and
running a C and a C++ program, one cross compiler per target (`<triplet>-gcc
-c`), `make`, `python3 -c 'import zlib, bz2'` and `node -e`. The run fails,
and no dev files are added to the release, if any check fails. QEMU uses KVM when the runner
offers it, TCG otherwise (slow but enough for these commands).

Shared steps (disk cleanup, packages, QEMU with KVM) are the composite action
`.github/actions/setup-host`, used by both workflows.

## Release assets (release tag)

A tag starts both workflows. `build-release.yml` creates the release with the
base images and its notes; this workflow's `release` job waits for that
release (up to 3 hours), uploads the dev files to it and adds a "Dev images"
section to the notes. The base files are usually there long before the dev
files.

| File | Content |
|------|---------|
| `linux-libre-vm-dev-<arch>.img.xz` | dev disk image (8 GB sparse, mostly empty, so it compresses well); split into `.partNN` pieces if over 2 GiB |
| `linux-libre-vmlinuz-dev-<arch>` | kernel to boot it with (built in `base`) |
| `cross-<triplet>.<host arch>.tar.gz` | each cross toolchain on its own (14 files) |
| `MANIFEST-dev-<arch>.txt` | source commits, runner image, cross `BUILD-INFO`, sizes |
| `linux-libre-vm-dev-src-<tag>.tar.xz` | corresponding source: toolchain submodules, pinned tarballs, linux-libre, build files |
| `SHA256SUMS-dev` | checksums of the dev files (`SHA256SUMS` is the base files') |

The dev files have names of their own (`-dev-`, `cross-`), so `vm/release.sh`
still finds the base image in the same release.
