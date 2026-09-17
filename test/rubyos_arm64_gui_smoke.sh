#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
elf="$root/build/baremetal/rubyos-arm64-gui/rubyos.elf"
serial_log="$root/build/rubyos-arm64-gui-serial.log"
bridge_log="$root/build/rubyos-arm64-gui-bridge.log"
capture="/tmp/rubyos-baremetal-desktop.bmp"
graphical_demo_capture="/tmp/rubyos-graphical-demo.bmp"
inspector_capture="/tmp/rubyos-inspector.bmp"
terminal_capture="/tmp/rubyos-terminal.bmp"
arcade_capture="/tmp/rubyos-arcade.bmp"
plasma_capture="/tmp/rubyos-plasma.bmp"
sprites_capture="/tmp/rubyos-sprites.bmp"
image_viewer_capture="/tmp/rubyos-image-viewer.bmp"
export_dir="$(mktemp -d /tmp/rubyos-gui-export.XXXXXX)"
port="$($root/build/host-ruby/bin/ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.local_address.ip_port; server.close')"

rm -f "$serial_log" "$bridge_log" "$capture" "$graphical_demo_capture" "$inspector_capture" \
    "$terminal_capture" "$arcade_capture" "$plasma_capture" "$sprites_capture" \
    "$image_viewer_capture"
REMOTEOS_SDL_MODE=headless SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    REMOTEOS_SDL_EXPORT_DIR="$export_dir" \
    "${REMOTEOS_SDL_BIN:-$root/services/remoteos-sdl/remoteos-sdl}" --listen-tcp "127.0.0.1:$port" \
    >"$bridge_log" 2>&1 &
bridge_pid=$!
cleanup() {
    if kill -0 "$bridge_pid" 2>/dev/null; then
        kill "$bridge_pid" 2>/dev/null || true
    fi
    wait "$bridge_pid" 2>/dev/null || true
    rm -rf "$export_dir"
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
grep -q 'interactive Ruby graphical demos: PASS' "$serial_log"
grep -q 'live Terminal, Monitor, and Inspector: PASS' "$serial_log"
grep -q 'host file transfer: PASS' "$serial_log"
grep -q 'editor navigation and explicit persistence: PASS' "$serial_log"
grep -q 'compositor desktop mechanics: PASS' "$serial_log"
grep -q 'SDL_ttf Ruby Font: PASS' "$serial_log"
grep -q 'PNG/JPEG image surfaces: PASS' "$serial_log"
grep -q 'SDL audio bridge: PASS' "$serial_log"
grep -q 'Ruby media canvas: PASS' "$serial_log"
grep -q 'Ruby arcade games: PASS' "$serial_log"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$serial_log"
test -s "$capture"
file "$capture" | grep -q '480 x 300'
test -s "$graphical_demo_capture"
file "$graphical_demo_capture" | grep -q '480 x 300'
test -s "$inspector_capture"
file "$inspector_capture" | grep -q '480 x 300'
test -s "$terminal_capture"
file "$terminal_capture" | grep -q '480 x 300'
test -s "$arcade_capture"
file "$arcade_capture" | grep -q '480 x 300'
test -s "$plasma_capture"
file "$plasma_capture" | grep -q '480 x 300'
test -s "$sprites_capture"
file "$sprites_capture" | grep -q '480 x 300'
test -s "$image_viewer_capture"
file "$image_viewer_capture" | grep -q '480 x 300'
test "$(cat "$export_dir/rubyos-host-export.txt")" = \
    'RubyOS host export from the bare-metal VFS.'
echo 'RubyOS bare-metal CRuby SDL remote desktop smoke: PASS'

if [[ "${RUBYOS_REQUIRE_MEDIA:-0}" == 1 ]]; then
    grep -q 'Ruby SDL 3D scene: PASS' "$serial_log"
    grep -q 'Ruby SDL A/V export and playback: PASS' "$serial_log"
fi
