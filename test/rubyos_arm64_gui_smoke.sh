#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-gui/rubyos.elf"
serial_log="$root/build/rubyos-arm64-gui-serial.log"
bridge_log="$root/build/rubyos-arm64-gui-bridge.log"
capture="/tmp/rubyos-baremetal-desktop.bmp"
port="$($root/build/host-ruby/bin/ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.local_address.ip_port; server.close')"

rm -f "$serial_log" "$bridge_log" "$capture"
RUBYOS_DESKTOP_MODE=headless SDL_VIDEODRIVER=dummy \
    "$root/bridge/rubyos_bridge" --listen-tcp "127.0.0.1:$port" \
    >"$bridge_log" 2>&1 &
bridge_pid=$!
cleanup() {
    if kill -0 "$bridge_pid" 2>/dev/null; then
        kill "$bridge_pid" 2>/dev/null || true
    fi
    wait "$bridge_pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 100); do
    grep -q 'listening on tcp' "$bridge_log" 2>/dev/null && break
    sleep 0.02
done
grep -q 'listening on tcp' "$bridge_log"

set +e
timeout 30s qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
    -nographic -monitor none -serial stdio -no-reboot \
    -device virtio-serial-device \
    -chardev socket,id=rubyos_bridge,host=127.0.0.1,port="$port" \
    -device virtconsole,chardev=rubyos_bridge \
    -kernel "$elf" </dev/null >"$serial_log" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$serial_log"
    cat "$bridge_log"
    exit "$status"
fi

cat "$serial_log"
cat "$bridge_log"
grep -q 'remote SDL desktop: PASS' "$serial_log"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$serial_log"
test -s "$capture"
file "$capture" | grep -q '480 x 300'
echo 'RubyOS bare-metal CRuby SDL remote desktop smoke: PASS'
