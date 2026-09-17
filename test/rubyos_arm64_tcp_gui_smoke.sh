#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
variant=tcp-gui
source "$root/test/guest-command.sh"
port="${RUBYOS_REMOTEOS_PORT:-17012}"
output="$(mktemp /tmp/rubyos-tcp-gui.XXXXXX)"
service_output="$(mktemp /tmp/rubyos-tcp-gui-service.XXXXXX)"
catalog_capture="/tmp/rubyos-catalog.bmp"
menu_capture="/tmp/rubyos-menu.bmp"

cleanup() {
    kill "${qemu_pid:-}" 2>/dev/null || true
    kill "${service_pid:-}" 2>/dev/null || true
    rm -f "$output" "$service_output" "$catalog_capture" "$menu_capture"
}
trap cleanup EXIT

"${guest[@]}" \
    -netdev user,id=rubyos-net,hostfwd=tcp:127.0.0.1:"$port"-:5001 \
    -device "${net_device},netdev=rubyos-net,mac=52:54:00:12:34:57" \
    </dev/null >"$output" 2>&1 &
qemu_pid=$!

REMOTEOS_SDL_MODE=headless SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    "${REMOTEOS_SDL_BIN:-$root/services/remoteos-sdl/remoteos-sdl}" \
    --connect-tcp "127.0.0.1:$port" --connect-timeout-ms 30000 \
    >"$service_output" 2>&1 &
service_pid=$!

for _ in $(seq 1 2400); do
    if grep -q 'RemoteOS over native TCP: PASS' "$output"; then
        break
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        cat "$output" "$service_output"
        exit 1
    fi
    sleep 0.05
done

cat "$output"
cat "$service_output"
grep -q 'RemoteOS TCP ready on 10.0.2.15:5001' "$output"
grep -q 'RemoteOS over native TCP: PASS' "$output"
grep -q 'remote SDL desktop: PASS' "$output"
grep -q 'categorized Ruby demo catalog: PASS' "$output"
grep -q 'menus and global shortcuts: PASS' "$output"
test -s "$catalog_capture"
file "$catalog_capture" | grep -q '480 x 300'
cp "$catalog_capture" "$root/build/rubyos-catalog.bmp"
test -s "$menu_capture"
file "$menu_capture" | grep -q '480 x 300'
cp "$menu_capture" "$root/build/rubyos-menu.bmp"
grep -q 'negotiated protocol v2 with client=rubyos' "$service_output"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output"
echo 'RubyOS bare-metal RemoteOS native TCP desktop: PASS'

if [[ "${RUBYOS_REQUIRE_MEDIA:-0}" == 1 ]]; then
    grep -q 'Ruby SDL 3D scene: PASS' "$output"
    grep -q 'Ruby SDL A/V export and playback: PASS' "$output"
fi
