#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# Fetch the self-hosting toolchain sources (see docs/self-hosting.md):
#
#   - git submodules under sources/toolchain/ (binutils, gcc, glibc, bc, perl),
#     shallow, by the release tag recorded in .gitmodules (`ref`), verified
#     against the commit pinned in the index. Fetching by tag avoids servers
#     that refuse to serve an arbitrary commit (which would otherwise force a
#     full-history clone — gcc is several GB).
#   - release tarballs (make, m4, bison, flex) into sources/toolchain/dist/,
#     verified by SHA-256.
#
# Usage: scripts/fetch-toolchain.sh [sources/toolchain/<name>...]
#        (default: all toolchain submodules, then the tarballs)
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DIST=sources/toolchain/dist

# name  sha256  url...
TARBALLS=(
  "make-4.4.1.tar.gz  dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3  https://ftpmirror.gnu.org/gnu/make/make-4.4.1.tar.gz https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz"
  "m4-1.4.21.tar.xz   f25c6ab51548a73a75558742fb031e0625d6485fe5f9155949d6486a2408ab66  https://ftpmirror.gnu.org/gnu/m4/m4-1.4.21.tar.xz https://ftp.gnu.org/gnu/m4/m4-1.4.21.tar.xz"
  "bison-3.8.2.tar.xz 9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2  https://ftpmirror.gnu.org/gnu/bison/bison-3.8.2.tar.xz https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
  "flex-2.6.4.tar.gz  e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995  https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz"
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

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

download() {
  if command -v curl >/dev/null; then curl -fsSL -o "$2" "$1"
  else wget -q -O "$2" "$1"; fi
}

# ── git sources ─────────────────────────────────────────────────────────────
if [ $# -gt 0 ]; then
  paths=("$@")
else
  paths=($(git config -f .gitmodules --get-regexp '\.path$' | awk '{ print $2 }' |
           grep '^sources/toolchain/'))
fi
for sm in "${paths[@]}"; do
  url=$(git config -f .gitmodules "submodule.$sm.url")
  ref=$(git config -f .gitmodules "submodule.$sm.ref")
  # Pinned commit: .gitmodules `commit` (always present) and the index gitlink
  # (present once the submodule is staged or committed) — they must agree
  pinned=$(git config -f .gitmodules "submodule.$sm.commit" || true)
  indexed=$(git ls-files -s -- "$sm" | awk '$1 == "160000" { print $2 }')
  if [ -n "$pinned" ] && [ -n "$indexed" ] && [ "$pinned" != "$indexed" ]; then
    echo "ERROR: $sm: .gitmodules pins $pinned but the index has $indexed" >&2; exit 1
  fi
  sha=${indexed:-$pinned}
  [ -n "$sha" ] || { echo "ERROR: $sm: no pinned commit (.gitmodules 'commit' or index)" >&2; exit 1; }

  if [ "$(git -C "$sm" rev-parse -q --verify HEAD 2>/dev/null)" = "$sha" ]; then
    echo "=== $sm: already at ${sha:0:12} (${ref#refs/tags/})"
    continue
  fi
  echo "=== $sm: fetching ${ref#refs/tags/} from $url"
  git submodule init -q -- "$sm"
  mkdir -p "$sm"
  git -C "$sm" rev-parse --git-dir >/dev/null 2>&1 &&
    [ "$(git -C "$sm" rev-parse --show-toplevel)" = "$(cd "$sm" && pwd -P)" ] ||
    git init -q "$sm"
  retry git -C "$sm" fetch -q --depth 1 "$url" "$ref"
  got=$(git -C "$sm" rev-parse 'FETCH_HEAD^{commit}')
  [ "$got" = "$sha" ] || {
    echo "ERROR: $ref is $got upstream, but $sm is pinned to $sha" >&2
    exit 1
  }
  git -C "$sm" checkout -q --detach "$sha"
done

# ── release tarballs ────────────────────────────────────────────────────────
mkdir -p "$DIST"
for entry in "${TARBALLS[@]}"; do
  read -r name want urls <<<"$entry"
  file=$DIST/$name
  if [ -f "$file" ] && [ "$(sha256 "$file")" = "$want" ]; then
    echo "=== $name: ok"
    continue
  fi
  ok=
  for url in $urls; do
    echo "=== $name: downloading $url"
    if retry download "$url" "$file.part" && [ "$(sha256 "$file.part")" = "$want" ]; then
      mv "$file.part" "$file"; ok=1; break
    fi
    echo "  checksum mismatch or download failed" >&2
  done
  rm -f "$file.part"
  [ -n "$ok" ] || { echo "ERROR: could not fetch $name with SHA-256 $want" >&2; exit 1; }
done

echo "=== Toolchain sources ready"
