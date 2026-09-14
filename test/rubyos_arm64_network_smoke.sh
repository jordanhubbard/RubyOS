#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-network/rubyos.elf"
output_file="$(mktemp /tmp/rubyos-network-output.XXXXXX)"
server_output="$(mktemp /tmp/rubyos-network-server.XXXXXX)"
client_output="$(mktemp /tmp/rubyos-network-client.XXXXXX)"
"$root/build/host-ruby/bin/ruby" "$root/test/tcp_echo_server.rb" >"$server_output" 2>&1 &
server_pid=$!
"$root/build/host-ruby/bin/ruby" "$root/test/tcp_guest_client.rb" >"$client_output" 2>&1 &
client_pid=$!
cleanup() {
    kill "$server_pid" 2>/dev/null || true
    kill "$client_pid" 2>/dev/null || true
    rm -f "$output_file"
    rm -f "$server_output"
    rm -f "$client_output"
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
    -netdev user,id=rubyos-net,hostfwd=tcp:127.0.0.1:17011-:17011 \
    -device virtio-net-device,netdev=rubyos-net,mac=52:54:00:12:34:56 \
    </dev/null >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'network: DHCP 52:54:00:12:34:56 10.0.2.15 gateway 10.0.2.2' "$output_file"
grep -q 'network: ICMP echo reply from 10.0.2.2' "$output_file"
grep -Eq 'network: DNS example.com -> [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ via 10.0.2.3' "$output_file"
grep -q 'network: TCP echo round trip via 10.0.2.2:18081' "$output_file"
grep -q 'network: Ruby REPL ready on 17011' "$output_file"
grep -q 'network: Ruby REPL evaluated => 4' "$output_file"
wait "$client_pid"
grep -q '=> 4' "$client_output"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal VirtIO network smoke: PASS'
