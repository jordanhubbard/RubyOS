#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
platform="${1:?usage: package-release.sh macos|linux}"
case "$platform" in macos|linux) ;; *) echo "unknown platform: $platform" >&2; exit 2 ;; esac

version="$(sed -n 's/^  VERSION = "\([^"]*\)"/\1/p' kernel/rubyos.rb)"
arch="$(uname -m)"
[[ "$arch" == arm64 ]] && arch=arm64
[[ "$arch" == aarch64 ]] && arch=arm64
bundle="rubyos-${version}-${platform}-${arch}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/rubyos-release.XXXXXX")"
stage="$temporary/$bundle"
trap 'rm -rf "$temporary"' EXIT

mkdir -p "$stage/bin" "$stage/runtime" "$stage/share/rubyos" dist
cp -f README.md LICENSE RELEASE-NOTES.md "$stage/"
cp -rf build/host-ruby/. "$stage/runtime/"
cp -f bridge/rubyos_bridge "$stage/bin/"
cp -rf config docs examples kernel "$stage/share/rubyos/"

if [[ "$platform" == linux ]]; then
    mkdir -p "$stage/images/arm64" "$stage/images/x86_64"
    for variant in rubyos-arm64 rubyos-arm64-gui rubyos-arm64-repl \
                   rubyos-arm64-storage rubyos-arm64-network rubyos-arm64-input \
                   rubyos-arm64-audio rubyos-arm64-smp; do
        cp -f "build/baremetal/$variant/rubyos.elf" "$stage/images/arm64/$variant.elf"
    done
    for variant in rubyos-x86_64 rubyos-x86_64-input rubyos-x86_64-audio \
                   rubyos-x86_64-smp; do
        cp -f "build/baremetal/$variant/rubyos.iso" "$stage/images/x86_64/$variant.iso"
    done
    cp -f build/disk.img "$stage/images/rubyos-ext2.img"
fi

archive="dist/$bundle.tar.gz"
tar -czf "$archive" -C "$temporary" "$bundle"
if command -v sha256sum >/dev/null 2>&1; then
    (cd dist && sha256sum "$(basename "$archive")") >"$archive.sha256"
else
    (cd dist && shasum -a 256 "$(basename "$archive")") >"$archive.sha256"
fi
printf 'release artifact: %s\n' "$archive"
