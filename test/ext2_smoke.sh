#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
temporary="$(mktemp -d /tmp/rubyos-ext2.XXXXXX)"
cleanup() {
    rm -rf "$temporary"
}
trap cleanup EXIT

mkdir -p "$temporary/root/home" "$temporary/root/apps/demo"
printf 'persistent ruby\n' >"$temporary/root/home/greeting.txt"
printf 'RubyOS\n' >"$temporary/root/apps/demo/name.txt"
head -c 70000 /dev/zero | tr '\0' R >"$temporary/root/home/large.bin"
truncate -s 16M "$temporary/disk.img"
mkfs.ext2 -q -F -t ext2 -b 4096 -d "$temporary/root" "$temporary/disk.img"

RUBYOS_EXT2_IMAGE="$temporary/disk.img" \
    "$root/build/host-ruby/bin/ruby" -I "$root/kernel" "$root/test/ext2_test.rb"
e2fsck -fn "$temporary/disk.img"
