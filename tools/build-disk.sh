#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="${1:-$root/build/disk.img}"
size_mb="${2:-16}"
staging="$(mktemp -d /tmp/rubyos-disk.XXXXXX)"
cleanup() {
    rm -rf "$staging"
}
trap cleanup EXIT

mkdir -p "$staging/home" "$staging/apps"
printf 'This file lives on the RubyOS ext2 disk.\n' >"$staging/home/persistent.txt"
printf 'Ruby objects are the operating system.\n' >"$staging/apps/README"
mkdir -p "$(dirname "$image")"
truncate -s "${size_mb}M" "$image"
mkfs.ext2 -q -F -t ext2 -b 4096 -L rubyos -d "$staging" "$image"
echo "RubyOS ext2 disk: $image (${size_mb} MiB)"
