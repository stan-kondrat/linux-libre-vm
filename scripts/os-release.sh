#!/bin/sh
# ═════════════════════════════════════════════════════════════════════════════
# Print the /etc/os-release of a dev image (stdout).
#
# Usage: scripts/os-release.sh RELEASE COMMIT
#   RELEASE  release tag, or "edge"
#   COMMIT   commit of this repository the image was built from
#
# Used wherever the release identity is written: dev-release.sh (the build),
# container-import.sh and retag-image.sh (a tag that publishes an earlier
# build).
# ═════════════════════════════════════════════════════════════════════════════

set -eu

cat <<OS
NAME="Super Minimal Linux Libre (dev)"
ID=linux-libre-vm
VERSION_ID="$1"
VERSION="$1"
BUILD_ID="$2"
PRETTY_NAME="Super Minimal Linux Libre dev $1"
HOME_URL="https://github.com/stan-kondrat/linux-libre-vm"
OS
