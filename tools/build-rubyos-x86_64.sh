#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^RUBY_VERSION := //p' "$root/config/ruby.mk")"
source="$root/build/ruby-build/ruby-$version"
ruby_build="$root/build/baremetal/ruby-freestanding-x86_64"
variant="${RUBYOS_X86_VARIANT:-rubyos-x86_64}"
out="$root/build/baremetal/$variant"
cflags=(-std=gnu11 -O2 -ffreestanding -fno-stack-protector -fno-pie -mno-red-zone -DARCH_X86_64 -I"$root/platform/libc/include" -I"$root/platform/boot")
mkdir -p "$out/libc" "$out/iso/boot/grub"
"$root/build/baremetal/host-ruby/bin/ruby" "$root/tools/embed-kernel.rb" > "$out/kernel_source.h"
nasm -f elf64 "$root/baremetal/x86_64/boot.asm" -o "$out/boot.o"
nasm -f elf64 "$root/baremetal/x86_64/interrupts.asm" -o "$out/interrupts.o"
nasm -f bin "$root/baremetal/x86_64/ap_trampoline.asm" -o "$out/ap_trampoline.bin"
(cd "$out" && x86_64-elf-ld -r -b binary ap_trampoline.bin -o ap_trampoline.o)
x86_64-elf-gcc "${cflags[@]}" -I"$source/include" -I"$ruby_build/.ext/include/x86_64-none" -I"$ruby_build" -I"$out" -c "$root/baremetal/x86_64/ruby_kernel.c" -o "$out/kernel.o"
x86_64-elf-gcc "${cflags[@]}" -c "$root/baremetal/arm64/platform_stubs.c" -o "$out/platform_stubs.o"
x86_64-elf-gcc "${cflags[@]}" -c "$root/baremetal/x86_64/tls.c" -o "$out/tls.o"
x86_64-elf-gcc "${cflags[@]}" -c "$root/baremetal/x86_64/interrupts.c" -o "$out/interrupts_c.o"
x86_64-elf-gcc "${cflags[@]}" -c "$root/baremetal/x86_64/smp.c" -o "$out/smp.o"
x86_64-elf-gcc "${cflags[@]}" -c "$root/baremetal/x86_64/setjmp.S" -o "$out/setjmp.o"
objects=()
for file in "$root"/platform/libc/*.c; do
    object="$out/libc/$(basename "${file%.c}").o"
    x86_64-elf-gcc "${cflags[@]}" -c "$file" -o "$object"
    objects+=("$object")
done
libgcc="$(x86_64-elf-gcc -print-libgcc-file-name)"
x86_64-elf-ld -z noexecstack -T "$root/baremetal/x86_64/linker.ld" -nostdlib -o "$out/rubyos.elf" "$out/boot.o" "$out/interrupts.o" "$out/ap_trampoline.o" "$out/kernel.o" "$out/platform_stubs.o" "$out/tls.o" "$out/interrupts_c.o" "$out/smp.o" "$out/setjmp.o" "${objects[@]}" --whole-archive "$ruby_build/libruby-static.a" --no-whole-archive "$libgcc"
cp -f "$out/rubyos.elf" "$out/iso/boot/rubyos.elf"
cp -f "$root/baremetal/x86_64/grub.cfg" "$out/iso/boot/grub/grub.cfg"
grub-mkrescue -o "$out/rubyos.iso" "$out/iso" >/dev/null 2>&1
echo "RubyOS x86_64 image: $out/rubyos.iso"
