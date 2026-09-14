#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_root/build/baremetal/arm64"
cc="${RUBYOS_ARM64_CC:-aarch64-elf-gcc}"
ld="${RUBYOS_ARM64_LD:-aarch64-elf-ld}"

cflags=(
    -std=c11 -O2 -ffreestanding -fno-stack-protector -fno-pie
    -Wall -Wextra -Werror -march=armv8-a
)

mkdir -p "$output_dir"

"$cc" "${cflags[@]}" -c "$project_root/baremetal/arm64/boot.S" \
    -o "$output_dir/boot.o"
"$cc" "${cflags[@]}" -c "$project_root/baremetal/arm64/kernel.c" \
    -o "$output_dir/kernel.o"
"$ld" -T "$project_root/baremetal/arm64/linker.ld" -nostdlib \
    -o "$output_dir/rubyos-arm64.elf" \
    "$output_dir/boot.o" "$output_dir/kernel.o"

"$cc" -print-libgcc-file-name >/dev/null
echo "built $output_dir/rubyos-arm64.elf"

