#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

check() {
    local os="$1" arch="$2" manager="$3" output
    output="$(RUBYOS_INSTALL_DRY_RUN=1 RUBYOS_INSTALL_OS="$os" \
        RUBYOS_INSTALL_UNAME_M="$arch" RUBYOS_INSTALL_PACKAGE_MANAGER="$manager" \
        RUBYOS_INSTALL_HAVE_DOCKER=0 \
        "$root/tools/install-host.sh")"
    grep -q 'git submodule update --init --recursive' <<<"$output"
    grep -q 'ensure Docker daemon is running' <<<"$output"
    grep -q "RubyOS host dependencies are ready ($os/$arch)" <<<"$output"
    printf '%s\n' "$output"
}

mac_arm="$(check Darwin arm64 '')"
grep -q 'brew install.*ffmpeg.*qemu' <<<"$mac_arm"
grep -q 'brew install --cask docker-desktop' <<<"$mac_arm"

mac_x86="$(check Darwin x86_64 '')"
grep -q 'brew install.*sdl2' <<<"$mac_x86"

linux_arm="$(check Linux aarch64 apt)"
grep -q 'apt-get install.*qemu-system-arm.*qemu-system-x86' <<<"$linux_arm"

linux_x86="$(check Linux x86_64 apt)"
grep -q 'apt-get install.*docker.io' <<<"$linux_x86"

for arch in aarch64 x86_64; do
    wsl="$(RUBYOS_INSTALL_DRY_RUN=1 RUBYOS_INSTALL_OS=Linux \
        RUBYOS_INSTALL_UNAME_M="$arch" RUBYOS_INSTALL_PACKAGE_MANAGER=apt \
        RUBYOS_INSTALL_HAVE_DOCKER=0 RUBYOS_INSTALL_WSL=1 \
        "$root/tools/install-host.sh")"
    grep -q 'apt-get install.*qemu-system-arm.*qemu-system-x86' <<<"$wsl"
    grep -q 'WSL2 detected' <<<"$wsl"
done

echo 'RubyOS host installer matrix: PASS'
