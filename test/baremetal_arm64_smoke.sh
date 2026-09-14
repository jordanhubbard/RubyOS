#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
kernel="$project_root/build/baremetal/arm64/rubyos-arm64.elf"
output_file="$(mktemp /tmp/rubyos-arm64-smoke.XXXXXX)"
cleanup() {
    rm -f "$output_file"
}
trap cleanup EXIT

set +e
timeout 8 qemu-system-aarch64 \
    -machine virt -cpu cortex-a57 -m 512M -smp 1 \
    -nographic -monitor none -serial stdio -no-reboot \
    -kernel "$kernel" </dev/null >"$output_file" 2>&1
status=$?
set -e

if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

grep -Fq "[RubyOS/arm64] boot: serial OK" "$output_file"
grep -Fq "[RubyOS/arm64] boot: EL1 and FPU ready" "$output_file"
grep -Fq "[RubyOS/arm64] next: freestanding CRuby" "$output_file"
cat "$output_file"
echo "RubyOS bare-metal ARM64 smoke: PASS"
