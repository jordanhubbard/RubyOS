#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-web/rubyos.elf"
port="${RUBYOS_WEB_HOST_PORT:-18080}"
output="$(mktemp /tmp/rubyos-web-output.XXXXXX)"
body="$(mktemp /tmp/rubyos-web-body.XXXXXX)"

cleanup() {
    kill "${qemu_pid:-}" 2>/dev/null || true
    rm -f "$output" "$body"
}
trap cleanup EXIT

qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot -kernel "$elf" \
    -netdev user,id=rubyos-net,hostfwd=tcp:127.0.0.1:"$port"-:8080 \
    -device virtio-net-device,netdev=rubyos-net,mac=52:54:00:12:34:58 \
    </dev/null >"$output" 2>&1 &
qemu_pid=$!

for _ in $(seq 1 400); do
    if curl --silent --show-error --max-time 1 "http://127.0.0.1:$port/" >"$body" 2>/dev/null; then
        break
    fi
    sleep 0.05
done

for _ in $(seq 1 100); do
    grep -q 'Rack-shaped HTTP server: PASS' "$output" && break
    sleep 0.02
done
cat "$output"
cat "$body"
grep -q 'RubyOS Rack-shaped server on CRuby 4.0.6' "$body"
grep -q 'HTTP ready on 10.0.2.15:8080' "$output"
grep -q 'Rack-shaped HTTP server: PASS' "$output"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output"
echo 'RubyOS bare-metal Rack-shaped HTTP server: PASS'
