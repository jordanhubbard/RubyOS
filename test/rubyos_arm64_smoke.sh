#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-cruby-arm64-smoke.XXXXXX)"
cleanup() {
    rm -f "$output_file"
}
trap cleanup EXIT

set +e
timeout 20s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    </dev/null >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'boot: RubyOS libc initialized' "$output_file"
grep -q 'boot: timer IRQs active' "$output_file"
grep -q 'RubyOS 0.0.1' "$output_file"
grep -q 'kernel: COM1 -> RubyOS::SerialDriver' "$output_file"
grep -q 'kernel: fibers \[\[0, :start\], \[1, :start\], \[0, :finish\], \[1, :finish\]\]' "$output_file"
grep -q 'kernel: timer \[:sleep, :wake\]' "$output_file"
grep -q 'kernel: memory ' "$output_file"
grep -q 'Ruby owns the machine' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS source-built CRuby ARM64 smoke: PASS'
