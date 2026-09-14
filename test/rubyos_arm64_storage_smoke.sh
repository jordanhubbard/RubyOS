#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-storage/rubyos.elf"
disk="$root/build/disk.img"
output_file="$(mktemp /tmp/rubyos-storage-output.XXXXXX)"
input_file="$(mktemp /tmp/rubyos-storage-input.XXXXXX)"
cleanup() {
    rm -f "$output_file" "$input_file"
}
trap cleanup EXIT
printf 'ls /home\ncat /home/persistent.txt\nwrite /home/from-ruby.txt durable-ruby\ncat /home/from-ruby.txt\nmkdir /home/remove-me\nrm /home/remove-me\nrm /home/from-ruby.txt\nls /home\nls /apps\ncat /apps/README\n' >"$input_file"

set +e
timeout 25s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    -drive if=none,file="$disk",format=raw,id=rubyos-disk \
    -device virtio-blk-device,drive=rubyos-disk \
    <"$input_file" >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'storage: ext2 .* sectors mounted at /home and /apps' "$output_file"
grep -q 'persistent.txt' "$output_file"
grep -q 'This file lives on the RubyOS ext2 disk.' "$output_file"
grep -q '12 bytes' "$output_file"
grep -q 'durable-ruby' "$output_file"
grep -q 'created /home/remove-me' "$output_file"
grep -q 'removed /home/remove-me' "$output_file"
grep -q 'removed /home/from-ruby.txt' "$output_file"
grep -q 'README' "$output_file"
grep -q 'Ruby objects are the operating system.' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
debugfs -R 'stat /home/from-ruby.txt' "$disk" 2>&1 | grep -q 'File not found'
e2fsck -fn "$disk"
echo 'RubyOS bare-metal VirtIO/ext2 storage smoke: PASS'
