#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-repl/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-repl-output.XXXXXX)"
input_file="$(mktemp /tmp/rubyos-repl-input.XXXXXX)"
cleanup() {
    rm -f "$output_file" "$input_file"
}
trap cleanup EXIT
printf '1 + 2\ndevices\ntasks\nls /\ncat /home/welcome.txt\nwrite /home/note hello-ruby\ncat /home/note\n' >"$input_file"

set +e
timeout 25s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    <"$input_file" >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'RubyOS console -- Ruby is the kernel' "$output_file"
grep -q 'rubyos> 1 + 2' "$output_file"
grep -q '=> 3' "$output_file"
grep -q 'COM1: RubyOS::SerialDriver' "$output_file"
grep -q 'ruby-task-0: complete' "$output_file"
grep -q 'tmp  home  apps' "$output_file"
grep -q 'Welcome to RubyOS. Ruby is the kernel.' "$output_file"
grep -q '10 bytes' "$output_file"
grep -q 'hello-ruby' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal CRuby REPL smoke: PASS'
