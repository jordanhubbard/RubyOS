#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^RUBY_VERSION := //p' "$root/config/ruby.mk")"
ruby_source="$root/build/ruby-build/ruby-$version"
ruby_build="$root/build/baremetal/ruby-freestanding"
variant="${RUBYOS_ARM64_VARIANT:-rubyos-arm64}"
out="$root/build/baremetal/$variant"
cflags=(-std=gnu11 -O2 -ffreestanding -fno-stack-protector -fno-pie
    -march=armv8-a -DARCH_ARM64 -I"$root/platform/libc/include"
    -I"$root/platform/boot")

mkdir -p "$out/libc"
"$root/build/baremetal/host-ruby/bin/ruby" "$root/tools/embed-kernel.rb" \
    > "$out/kernel_source.h"
aarch64-elf-gcc "${cflags[@]}" -c "$root/baremetal/arm64/boot.S" -o "$out/boot.o"
aarch64-elf-gcc "${cflags[@]}" -I"$ruby_source/include" \
    -I"$ruby_build/.ext/include/aarch64-none" -I"$ruby_build" -I"$out" \
    -c "$root/baremetal/arm64/ruby_kernel.c" -o "$out/kernel.o"
aarch64-elf-gcc "${cflags[@]}" -c "$root/baremetal/arm64/platform_stubs.c" \
    -o "$out/platform_stubs.o"
aarch64-elf-gcc "${cflags[@]}" -c "$root/baremetal/arm64/gic_timer.c" \
    -o "$out/gic_timer.o"
aarch64-elf-gcc "${cflags[@]}" -c "$root/baremetal/arm64/setjmp.S" -o "$out/setjmp.o"

libc_objects=()
for source in "$root"/platform/libc/*.c; do
    object="$out/libc/$(basename "${source%.c}").o"
    aarch64-elf-gcc "${cflags[@]}" -c "$source" -o "$object"
    libc_objects+=("$object")
done

libgcc="$(aarch64-elf-gcc -print-libgcc-file-name)"
aarch64-elf-ld -T "$root/baremetal/arm64/linker.ld" -nostdlib \
    -o "$out/rubyos.elf" "$out/boot.o" "$out/kernel.o" \
    "$out/platform_stubs.o" "$out/gic_timer.o" "$out/setjmp.o" "${libc_objects[@]}" \
    --whole-archive "$ruby_build/libruby-static.a" --no-whole-archive "$libgcc"

if readelf -l "$out/rubyos.elf" | grep -q INTERP; then
    echo "freestanding kernel unexpectedly contains an ELF interpreter" >&2
    exit 1
fi
echo "RubyOS ARM64 kernel: $out/rubyos.elf"
