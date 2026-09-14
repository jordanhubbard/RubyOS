#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-network/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-network-output.XXXXXX)"
cleanup() {
    rm -f "$output_file"
}
trap cleanup EXIT

set +e
timeout 20s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    -netdev user,id=rubyos-net -device virtio-net-device,netdev=rubyos-net,mac=52:54:00:12:34:56 \
    </dev/null >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'network: 52:54:00:12:34:56 10.0.2.15' "$output_file"
grep -q 'network: ICMP echo reply from 10.0.2.2' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal VirtIO network smoke: PASS'
