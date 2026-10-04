#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# Fetch every submodule at its pinned commit, shallow (depth 1).
#
# Replaces `git submodule update --init --recursive`, which is slow and flaky
# against the upstream hosts:
#   - it clones full history (linux-libre alone is ~1 GB),
#   - --recursive clones a full gnulib into coreutils, grep, sed, ... even
#     though the build uses sources/gnulib via GNULIB_SRCDIR,
#   - git.savannah.gnu.org returns HTTP 500 under parallel load.
#
# Submodules are fetched one at a time, with retries. The only nested
# submodule the build needs is tar's paxutils.
#
# Usage: scripts/fetch-submodules.sh [path...]   (default: all submodules
#                                                 except sources/toolchain/*)
#        scripts/fetch-submodules.sh sources/tar/paxutils   (nested only)
#
# The toolchain sources (gcc, glibc, ... under sources/toolchain/) are large
# and only needed for the self-hosting toolchain: scripts/fetch-toolchain.sh.
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Savannah's git:// daemon (tar's nested paxutils uses it) refuses fetches of
# a specific commit; its HTTPS endpoint allows them.
GIT_URL_REWRITES=(
  -c url.https://git.savannah.gnu.org/git/.insteadOf=git://git.sv.gnu.org/
  -c url.https://git.savannah.gnu.org/git/.insteadOf=git://git.savannah.gnu.org/
)

retry() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    echo "  attempt $i failed; retrying in $((i * 20))s" >&2
    sleep $((i * 20))
  done
  return 1
}

# fetch_pinned <superproject dir> <submodule path>
fetch_pinned() {
  local top=$1 sm=$2 name url sha dir
  dir="$top/$sm"
  name=$(git -C "$top" config -f .gitmodules --get-regexp '\.path$' |
    awk -v p="$sm" '$2 == p { sub(/^submodule\./, "", $1); sub(/\.path$/, "", $1); print $1 }')
  url=$(git -C "$top" config -f .gitmodules "submodule.$name.url")
  # Pinned commit from the index (also works before the submodule is committed)
  sha=$(git -C "$top" ls-files -s -- "$sm" | awk '$1 == "160000" { print $2 }')
  [ -n "$sha" ] || { echo "ERROR: $sm is not a submodule in $top" >&2; return 1; }

  if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" = "$sha" ]; then
    echo "=== $dir: already at ${sha:0:12}"
    return 0
  fi

  echo "=== $dir: fetching ${sha:0:12} from $url"
  git -C "$top" submodule init -q -- "$sm"
  # Reuse an existing checkout (checkout refuses to clobber local changes)
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 &&
    [ "$(git -C "$dir" rev-parse --show-toplevel)" = "$(cd "$dir" && pwd -P)" ] ||
    git init -q "$dir"
  # Shallow fetch of the pinned commit; fall back to full history for
  # servers that refuse to serve an arbitrary commit.
  retry git "${GIT_URL_REWRITES[@]}" -C "$dir" fetch -q --depth 1 "$url" "$sha" ||
    retry git "${GIT_URL_REWRITES[@]}" -C "$dir" fetch -q "$url" "$sha" ||
    retry git "${GIT_URL_REWRITES[@]}" -C "$dir" fetch -q "$url" '+refs/heads/*:refs/remotes/origin/*'
  git -C "$dir" rev-parse -q --verify "$sha^{commit}" >/dev/null ||
    { echo "ERROR: $sha not found in $url" >&2; return 1; }
  git -C "$dir" checkout -q --detach "$sha"
}

if [ $# -gt 0 ]; then
  paths=("$@")
else
  paths=($(git config -f .gitmodules --get-regexp '\.path$' | awk '{ print $2 }' |
    grep -v '^sources/toolchain/'))
fi

for sm in "${paths[@]}"; do
  if [ "$sm" = sources/tar/paxutils ]; then
    fetch_pinned sources/tar paxutils
    continue
  fi
  fetch_pinned . "$sm"
  if [ "$sm" = sources/tar ]; then
    fetch_pinned sources/tar paxutils
  fi
done

echo "=== All submodules fetched"
