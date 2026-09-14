# RubyOS

RubyOS explores the same inversion as PythonOS with Ruby at its center: a
minimal assembly/C substrate starts CRuby, then Ruby objects own the kernel,
drivers, scheduler, filesystem, network stack, desktop, and applications.

This project builds Ruby from the official upstream source archive. It does
not use a system Ruby package, a system `ruby` executable, or a system
`libruby`. The pinned version and checksum live in `config/ruby.mk`.

## Current vertical slice

The first slice proves the language-level architecture on a source-built CRuby:

- Ruby 4.0.6 bootstrapped and installed privately in `build/host-ruby`
- the same CRuby source cross-built as a freestanding ARM64 static runtime
- a cooperative `Fiber` kernel scheduler
- ARM generic-counter monotonic time, sleeping, and a Ruby session clock
- a Ruby VFS/tmpfs with mount routing and file-descriptor semantics
- Ruby-native Ethernet, ARP, IPv4, ICMP, and UDP packet objects
- `Device`, `Driver`, and `Bus` object protocols
- a Ruby-native `Element -> View -> Container/Label -> Button` GUI hierarchy
- a Ruby compositor with focus/z-order, windows, menu bar, dock, and system apps
- a forked SDL2 companion plus an idiomatic Ruby
  `Transport -> Client -> Surface -> RemoteDesktop` hierarchy
- PythonOS-compatible length-prefixed bridge framing
- a QEMU kernel that enters CRuby with the RubyOS libc and boots the real
  Ruby object model
- boot smoke tests and a dependency-free hosted test suite

Run it with:

```sh
make smoke
make test
make test-ext2
make test-network
make test-bridge
make embed-probe
make baremetal-smoke
make ruby-arm64
make rubyos-arm64-smoke
make rubyos-arm64-gui-smoke
make rubyos-arm64-repl-smoke
make rubyos-arm64-storage-smoke
make rubyos-arm64-network-smoke
make provenance
```

`make embed-probe` also links a C executable directly against the privately
built `libruby-static.a`, enters through CRuby's embedding lifecycle, and
evaluates the first RubyOS kernel object. The hosted slice remains a fast
porting harness; `make rubyos-arm64-smoke` is the real freestanding gate.

The ARM64 substrate already boots independently under QEMU and proves the
EL2-to-EL1 transition, FPU enablement, stack/BSS initialization, and PL011
serial path. It is built with the freestanding `aarch64-elf` toolchain inside
the local builder image, not with the host Linux compiler.

That builder also cross-compiles the pinned CRuby source into an ARM64 static
archive and links it only with RubyOS's freestanding platform layer and
`libgcc`. The resulting ELF has no program interpreter and boots CRuby 4.0.6,
Prism, Ruby-defined devices, and cooperative Fibers on QEMU's `virt` machine.

The initial platform libc is adapted from PythonOS and retains its BSD license
in `platform/PYTHONOS-LICENSE`.

## SDL remote desktop

`make test-bridge` builds `bridge/rubyos_bridge` and uses the privately built
Ruby—not a system interpreter—to open a hidden SDL desktop, draw the GUI object
tree, present it, poll input, capture it, and shut it down.

`make rubyos-arm64-gui-smoke` proves the same path from the actual freestanding
kernel. Ruby code discovers a VirtIO console, negotiates its queues through
five tiny MMIO/DMA HAL primitives, encodes protocol JSON in pure Ruby, drives
the SDL companion, and captures a 480x300 desktop. PL011 remains an independent
boot and failure console.

For the visible exploratory desktop, run these in two terminals:

```sh
make bridge
RUBYOS_DESKTOP_MODE=interactive \
  bridge/rubyos_bridge --listen-tcp 127.0.0.1:17010
```

```sh
build/host-ruby/bin/ruby -I kernel examples/remote_desktop.rb
```

The wire protocol is currently unauthenticated and unencrypted. Keep it on
loopback or a trusted private/SSH-forwarded connection. VirtIO console is the
current bare-metal transport; a future TCP transport can implement the same
small byte-stream interface without changing the SDL or Ruby object layers.

The bare-metal desktop is composed by Ruby objects rather than a fixed bridge
scene. `Compositor` owns window focus and z-order, while `Application`
subclasses build About, Files, Terminal, and System Monitor windows from live
kernel state. SDL mouse events are normalized by the bridge and routed through
Ruby hit testing; the bare-metal smoke clicks the dock to launch and focus the
System Monitor. The SDL companion remains a rendering and input device.

## Bare-metal Ruby console

`make rubyos-arm64-repl-smoke` builds the console kernel and drives its PL011
input under QEMU. The prompt evaluates ordinary Ruby and provides `help`,
`version`, `devices`, `tasks`, `uptime`, `sleep`, `time`, `ls`, `cat`, and
`write` commands backed by live kernel objects.

`make rubyos-arm64-storage-smoke` adds a generated ext2 disk to QEMU. Ruby
discovers it through a Ruby VirtIO-MMIO block driver, parses ext2 without a C
filesystem library, and mounts its persistent `/home` and `/apps` trees into
the VFS. Files created or replaced from the Ruby shell are allocated and
written back to the disk. Ext2 deletion, arbitrary shrinking, and allocation
beyond single-indirect blocks remain later storage work.

`make rubyos-arm64-network-smoke` attaches QEMU user networking and proves a
Ruby-owned VirtIO-MMIO NIC, ARP resolution, IPv4, and ICMP by receiving an echo
reply from the virtual gateway. It then completes a TCP handshake and payload
round trip to a source-built-Ruby host service. The interface address, gateway,
netmask, DNS server, and lease time come from a Ruby DHCP client. Packet framing,
checksums, DNS compression parsing, and connection sequencing are ordinary Ruby
objects. A host-forwarded connection also exercises the server-side TCP
handshake and evaluates Ruby through the freestanding kernel's TCP REPL.

For an interactive session:

```sh
make rubyos-arm64-repl
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
  -nographic -monitor none -serial stdio \
  -kernel build/baremetal/rubyos-arm64-repl/rubyos.elf
```
