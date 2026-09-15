# RubyOS v0.1.0

## Ruby has taken the machine

RubyOS 0.1.0 is the first public release of an operating system in which CRuby
is not a scripting accessory politely waiting above a conventional kernel.
CRuby 4.0.6, built from pristine upstream source because distribution packages
have enjoyed quite enough leisure, *is* the kernel runtime.

Assembly and a deliberately small C substrate establish the machine. Then Ruby
objects take over scheduling, memory, devices, filesystems, network protocols,
the desktop, applications, games, and the suspiciously enjoyable fake-classic
chipset laboratory. This is objects all the way down, until the MMIO register
refuses to respond to `#map`.

## Two architectures, one very Ruby operating system

- ARM64 boots through EL1, GIC timers, PSCI SMP, and native VirtIO block,
  network, keyboard, pointer, and sound devices.
- x86_64 boots through GRUB and long mode with IDT/PIT interrupts, PS/2 input,
  Intel HDA DMA, and APIC INIT/SIPI worker bring-up.
- Both run the same source-built CRuby 4.0.6 and embedded Ruby kernel classes.
- CRuby remains safely on its GVL-owning bootstrap CPU while Ruby dispatches
  explicitly C-safe jobs to native application-processor mailboxes. We chose
  correctness over the traditional concurrency benchmark of "it worked once."

## A desktop Rubyists can actually poke

The SDL companion is a remote hardware device, not the author of the scene.
Ruby owns the compositor, windows, focus, hit testing, widgets, dock, menu,
Terminal, Editor, Files, Monitor, Clock, Settings, Image Viewer, Invaders, and
Snake. PNG/JPEG decoding, SDL_ttf fonts, canonical input events, PCM mixing,
and framebuffer captures all cross the same small transport boundary.

The chipset workbench adds dual playfields, display lists, Copper operations,
sprites, blits, and four-channel Paula-style audio. Modern computers are very
powerful, so naturally we used one to lovingly reconstruct the constraints
that made old computers interesting.

## Storage, networking, and debugging without hand-waving

Ruby implements writable ext2—including sparse files and double-indirect block
traversal—over a native VirtIO block queue. The network stack handles Ethernet,
ARP, IPv4, ICMP, UDP, DHCP, DNS, and TCP, including simultaneous remote Ruby
console sessions.

Every native run retains an independent serial failure plane. Debug sessions
add QMP control, GDB-remote symbols, SDL captures, guest round-trip timing, and
host service-time metrics. `make parity` tests the whole arrangement on ARM64
and x86_64 because "the architecture is elegant" is not a boot log.

## Builds and artifacts

- Linux CI builds and executes the complete bare-metal matrix, then packages
  the source-built host runtime, SDL bridge, ARM64 ELFs, x86_64 ISOs, and ext2
  disk image.
- macOS CI builds CRuby from source, runs the hosted Ruby kernel and SDL suite,
  and packages a self-contained Apple Silicon host bundle.
- Windows development uses the Linux contract under WSL2. There is no pretend
  native Windows port hiding behind a green YAML rectangle.

## Executive summary

RubyOS boots real machines, drives real emulated devices, presents a real
desktop, and puts idiomatic Ruby objects where an operating system normally
puts several million lines of somebody else's opinions. Version 0.1.0 is the
point where the experiment becomes a release—and the burden of explaining why
your language cannot implement a NIC driver returns to everyone else.

[Download RubyOS v0.1.0](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.1.0)
