#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-network/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-network-output.XXXXXX)"
server_output="$(mktemp /tmp/rubyos-network-server.XXXXXX)"
"$root/build/host-ruby/bin/ruby" "$root/test/tcp_echo_server.rb" >"$server_output" 2>&1 &
server_pid=$!
cleanup() {
    kill "$server_pid" 2>/dev/null || true
    rm -f "$output_file"
    rm -f "$server_output"
}
trap cleanup EXIT
for _ in $(seq 1 100); do
    if ss -ltn | grep -q ':18081 '; then
        break
    fi
    sleep 0.01
done

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
grep -q 'network: TCP echo round trip via 10.0.2.2:18081' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal VirtIO network smoke: PASS'
