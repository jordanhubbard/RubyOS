# Shared QEMU launch configuration for the same tests on both guest CPUs.
# Source after setting root and variant (repl, storage, network, web, tcp-gui).
arch="${RUBYOS_TEST_ARCH:-arm64}"
case "$arch" in
    arm64)
        guest=(qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M
            -nographic -monitor none -serial stdio -no-reboot
            -kernel "$root/build/baremetal/rubyos-arm64-$variant/rubyos.elf")
        net_device=virtio-net-device
        block_device=virtio-blk-device
        ;;
    x86_64)
        guest=(qemu-system-x86_64 -M pc -m 512M
            -nographic -monitor none -serial stdio -no-reboot
            -cdrom "$root/build/baremetal/rubyos-x86_64-$variant/rubyos.iso")
        net_device=virtio-net-pci,disable-legacy=on
        block_device=virtio-blk-pci,disable-legacy=on
        ;;
    *) echo "unsupported test architecture: $arch" >&2; exit 2 ;;
esac
