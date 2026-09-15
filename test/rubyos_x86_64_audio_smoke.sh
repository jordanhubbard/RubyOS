#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
iso="$root/build/baremetal/rubyos-x86_64-audio/rubyos.iso"
output_file="$(mktemp /tmp/rubyos-x86-audio.XXXXXX)"
cleanup() { rm -f "$output_file"; }
trap cleanup EXIT

set +e
timeout 20s qemu-system-x86_64 -m 768M -cdrom "$iso" \
    -display none -serial file:"$output_file" -no-reboot -no-shutdown \
    -audiodev driver=none,id=rubyos-audio \
    -device intel-hda -device hda-output,audiodev=rubyos-audio
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'native HDA sound DMA: PASS' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal x86_64 HDA sound smoke: PASS'
