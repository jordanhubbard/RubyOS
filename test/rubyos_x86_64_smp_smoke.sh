#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
iso="$root/build/baremetal/rubyos-x86_64-smp/rubyos.iso"
output_file="$(mktemp /tmp/rubyos-x86-smp.XXXXXX)"
cleanup() { rm -f "$output_file"; }
trap cleanup EXIT

set +e
timeout 30s qemu-system-x86_64 -m 768M -smp 4 -cdrom "$iso" \
    -display none -serial file:"$output_file" -no-reboot -no-shutdown
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'SMP 4/4 with 3 native jobs: PASS' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal x86_64 SMP workers smoke: PASS'
