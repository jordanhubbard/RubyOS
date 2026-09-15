#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-gui/rubyos.elf"
serial_log="$root/build/rubyos-arm64-gui-serial.log"
bridge_log="$root/build/rubyos-arm64-gui-bridge.log"
capture="/tmp/rubyos-baremetal-desktop.bmp"
port="$($root/build/host-ruby/bin/ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.local_address.ip_port; server.close')"

rm -f "$serial_log" "$bridge_log" "$capture"
REMOTEOS_SDL_MODE=headless SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    "$root/services/remoteos-sdl/remoteos-sdl" --listen-tcp "127.0.0.1:$port" \
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
    -chardev socket,id=remoteos_sdl,host=127.0.0.1,port="$port" \
    -device virtconsole,chardev=remoteos_sdl \
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
grep -q 'SDL input routing: PASS' "$serial_log"
grep -q 'keyboard Terminal input: PASS' "$serial_log"
grep -q 'core desktop apps: PASS' "$serial_log"
grep -q 'compositor desktop mechanics: PASS' "$serial_log"
grep -q 'SDL_ttf Ruby Font: PASS' "$serial_log"
grep -q 'PNG/JPEG image surfaces: PASS' "$serial_log"
grep -q 'SDL audio bridge: PASS' "$serial_log"
grep -q 'Ruby chipset workbench: PASS' "$serial_log"
grep -q 'dual-playfield chipset clock: PASS' "$serial_log"
grep -q 'Ruby arcade games: PASS' "$serial_log"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$serial_log"
test -s "$capture"
file "$capture" | grep -q '480 x 300'
echo 'RubyOS bare-metal CRuby SDL remote desktop smoke: PASS'
