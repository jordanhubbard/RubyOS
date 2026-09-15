#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-smp/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-arm-smp.XXXXXX)"
cleanup() { rm -f "$output_file"; }
trap cleanup EXIT

set +e
timeout 20s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 768M -smp 4 \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    </dev/null >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'SMP 4/4 with 3 native jobs: PASS' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal ARM64 SMP workers smoke: PASS'
