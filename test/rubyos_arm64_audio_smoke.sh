#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-audio/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-audio-output.XXXXXX)"
cleanup() { rm -f "$output_file"; }
trap cleanup EXIT

set +e
timeout 20s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    -audiodev driver=none,id=rubyos-audio \
    -device virtio-sound-device,audiodev=rubyos-audio \
    </dev/null >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'native VirtIO sound DMA: PASS' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal ARM64 VirtIO sound smoke: PASS'
