#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Download a GitHub release of this project (kernel + disk image) for the VM
# runners, so a VM can be created without building anything.
#
# Files are cached in vm/cache/release/<tag>/ and checked against the
# release's SHA256SUMS; a file already in the cache is not downloaded again.
# The compressed image (.img.xz) is preferred and unpacked with python3 (macOS
# has no xz command).
#
# Usage: vm/release.sh <command>
#   fetch ARCH   download if needed; print KERNEL=<path> and DISK=<path>
#   tag          print the tag VM_RELEASE resolves to
#   list         published releases, newest first
#   help
#
# Environment:
#   VM_RELEASE  release tag, or "latest"   (default: latest)
#   VM_REPO     GitHub owner/repo           (default: from the git remote
#                                            "origin", else stan-kondrat/linux-libre-vm)
#   GH_TOKEN    optional, raises the GitHub API rate limit for "latest"/list
#   VM_RELEASE_URL  base URL of the release assets, <url>/<tag>/<file>
#               (default: https://github.com/$VM_REPO/releases/download)
# ═════════════════════════════════════════════════════════════════════════════

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
CACHE=$HERE/cache/release
VM_RELEASE=${VM_RELEASE:-latest}

die() { echo "release.sh: $*" >&2; exit 1; }
say() { echo "release.sh: $*" >&2; }

if [ -z "${VM_REPO:-}" ]; then
	url=$(git -C "$HERE/.." remote get-url origin 2>/dev/null || true)
	VM_REPO=$(printf %s "$url" | sed -n 's|.*github\.com[:/]\([^/]*/[^/]*\)$|\1|p' | sed 's|\.git$||')
	VM_REPO=${VM_REPO:-stan-kondrat/linux-libre-vm}
fi
API=https://api.github.com/repos/$VM_REPO
DL=${VM_RELEASE_URL:-https://github.com/$VM_REPO/releases/download}

if command -v sha256sum >/dev/null; then sha256() { sha256sum "$1" | cut -d' ' -f1; }
else sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi

# GET a GitHub API path into $BODY (a temp file); the HTTP status goes to
# $HTTP (000: no connection). Returns non-zero unless the status is 200.
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT
api() {
	HTTP=$(curl -sS -L -o "$BODY" -w '%{http_code}' \
		-H 'Accept: application/vnd.github+json' \
		${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "$API/$1" 2>/dev/null) || HTTP=000
	[ "$HTTP" = 200 ]
}

# Newest tag already in the cache (offline fallback for "latest")
cached_tag() {
	ls -t "$CACHE" 2>/dev/null | while read -r t; do
		[ -f "$CACHE/$t/SHA256SUMS" ] && { echo "$t"; break; }
	done
}

cmd_tag() {
	[ "$VM_RELEASE" = latest ] || { echo "$VM_RELEASE"; return; }
	if api releases/latest; then
		python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$BODY"
		return
	fi
	case $HTTP in
	404) die "no release published yet in $VM_REPO. Build locally (make build install disk-image) and use VM_SOURCE=local." ;;
	000) t=$(cached_tag)
	     [ -n "$t" ] || die "cannot reach GitHub and nothing is cached in $CACHE"
	     say "cannot reach GitHub; using cached release $t"
	     echo "$t" ;;
	403 | 429) die "GitHub API rate limit reached; set GH_TOKEN or VM_RELEASE=<tag> (see: vm/release.sh list)" ;;
	*) die "GitHub API error $HTTP for $API/releases/latest" ;;
	esac
}

# Expected SHA-256 of a release asset, from SHA256SUMS
sum_of() { awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' "$DIR/SHA256SUMS"; }

# download NAME: fetch release asset NAME into $DIR (verified), unless cached
download() {
	want=$(sum_of "$1")
	[ -n "$want" ] || die "$1 is not in SHA256SUMS of $TAG"
	if [ -f "$DIR/$1" ] && [ "$(sha256 "$DIR/$1")" = "$want" ]; then return 0; fi
	say "downloading $1 ($TAG)"
	curl -fL --progress-bar -o "$DIR/$1.part" "$DL/$TAG/$1" || die "download failed: $DL/$TAG/$1"
	[ "$(sha256 "$DIR/$1.part")" = "$want" ] || { rm -f "$DIR/$1.part"; die "checksum mismatch: $1"; }
	mv "$DIR/$1.part" "$DIR/$1"
}

cmd_fetch() {
	arch=${1:-}
	case $arch in x86_64 | arm64) ;; *) die "usage: release.sh fetch x86_64|arm64" ;; esac
	TAG=$(cmd_tag)
	DIR=$CACHE/$TAG
	mkdir -p "$DIR"
	if [ ! -f "$DIR/SHA256SUMS" ]; then
		curl -fsL -o "$DIR/SHA256SUMS.part" "$DL/$TAG/SHA256SUMS" ||
			{ rmdir "$DIR" 2>/dev/null; die "release $TAG not found in $VM_REPO (see: vm/release.sh list)"; }
		mv "$DIR/SHA256SUMS.part" "$DIR/SHA256SUMS"
	fi

	kernel=linux-libre-vmlinuz-$arch
	img=linux-libre-vm-$arch.img
	download "$kernel"
	raw_sum=$(sum_of "$img")
	if [ -f "$DIR/$img" ] && { [ -z "$raw_sum" ] || [ "$(sha256 "$DIR/$img")" = "$raw_sum" ]; }; then
		:  # cached
	elif [ -n "$(sum_of "$img.xz")" ]; then
		download "$img.xz"
		say "unpacking $img.xz"
		python3 - "$DIR/$img.xz" "$DIR/$img.part" <<-'EOF'
		import lzma, shutil, sys
		with lzma.open(sys.argv[1]) as src, open(sys.argv[2], "wb") as dst:
		    shutil.copyfileobj(src, dst, 1 << 20)
		EOF
		[ -z "$raw_sum" ] || [ "$(sha256 "$DIR/$img.part")" = "$raw_sum" ] ||
			{ rm -f "$DIR/$img.part"; die "checksum mismatch after unpacking $img.xz"; }
		mv "$DIR/$img.part" "$DIR/$img"
		rm -f "$DIR/$img.xz"
	else
		download "$img"
	fi
	echo "KERNEL=$DIR/$kernel"
	echo "DISK=$DIR/$img"
}

cmd_list() {
	api 'releases?per_page=20' || die "GitHub API error $HTTP for $API/releases"
	python3 - "$BODY" <<-'EOF'
	import json, sys
	rel = json.load(open(sys.argv[1]))
	if not rel:
	    print("no releases published yet")
	for r in rel:
	    date = (r["published_at"] or "draft")[:10]
	    pre = " (pre-release)" if r["prerelease"] else ""
	    print("%-20s %s%s" % (r["tag_name"], date, pre))
	EOF
	t=$(ls "$CACHE" 2>/dev/null | tr '\n' ' ')
	[ -z "$t" ] || echo "cached: $t($CACHE)"
}

cmd=${1:-help}
[ $# -gt 0 ] && shift
case $cmd in
fetch) cmd_fetch "$@" ;;
tag)   cmd_tag ;;
list)  cmd_list ;;
help | -h | --help) awk 'NR > 2 && /^# ═/ { exit } NR > 2' "$0" | sed 's/^# \{0,1\}//' ;;
*)     awk 'NR > 2 && /^# ═/ { exit } NR > 2' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
