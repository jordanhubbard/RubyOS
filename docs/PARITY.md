# PythonOS feature parity

This ledger compares behavior, not implementation language. RubyOS should feel
native to Ruby while offering the same useful system surfaces as PythonOS.

| Area | PythonOS baseline | RubyOS evidence | Status |
|---|---|---|---|
| Source-built language runtime | Cross-built CPython | CRuby 4.0.6, Prism, static ARM64 ELF | Complete |
| Bare-metal boot | x86_64 and ARM64, exceptions, timers | ARM64 EL1/FPU/TLS/exceptions and generic counter | Partial |
| Scheduler | asyncio tasks, timers, AP workers | Cooperative Ruby Fibers, timed sleep/deadline queue, monotonic `Timekeeper` | Partial |
| Interactive shell | serial and multi-session TCP REPL, commands, editor | bare-metal serial commands and single-session TCP Ruby evaluation | Partial |
| Device model | buses and typed drivers | `Bus`, `Device`, `Driver` mixin | Partial |
| Memory | physical allocator, DMA, mmap, heap metrics | buddy heap, mmap shim, DMA HAL | Partial |
| Storage | VFS, tmpfs, ext2, mounted persistent `/home` | Ruby VFS/tmpfs plus writable ext2 over bare-metal VirtIO block at `/home` and `/apps` | Partial |
| Network | VirtIO net, Ethernet, ARP, IPv4, ICMP, UDP, TCP, DHCP, DNS | bare-metal Ruby VirtIO net, DHCP, ARP, IPv4/ICMP, UDP, DNS, TCP client/server | Partial |
| Remote display | UART/VirtIO/TCP protocol-v1 SDL companion | hosted TCP and bare-metal VirtIO console | Complete |
| GUI API | SDL-compatible surfaces, events, images, fonts | Ruby `Surface` and basic widget hierarchy | Partial |
| Desktop | compositor, windows, menu bar, dock, wallpaper, shortcuts | Ruby compositor, focus/z-order, windows, menu bar, dock | Partial |
| Apps | terminal, editor, files, image viewer, monitor, clock, settings | About, Files, Terminal, VFS Editor, Image Viewer, System Monitor | Partial |
| Demos and games | graphics/audio demos and arcade games | none | Missing |
| Input | PS/2 and VirtIO input, canonical event queue | SDL event queue routed through Ruby window and dock hit testing | Partial |
| Audio | AC97/Intel HDA/bridge mixer and sound API | Ruby PCM/waveform mixer and bare-metal SDL audio bridge | Partial |
| Images | PNG/JPEG decoding and viewer | Ruby remote surfaces, raw upload, PNG/JPEG decode/blit, Image Viewer | Partial |
| Chipset laboratory | display lists, copper/blitter/sprites/audio | none | Missing |
| Concurrency | ARM64/x86 SMP, pthread substrate, no-GIL workers | single-core pthread compatibility | Missing |
| Debug/automation | QMP/native debug, captures, performance metrics | deterministic QEMU smokes and SDL captures | Partial |
| Teaching examples | curated storage/network/graphics/audio/internals lessons | one remote desktop example | Missing |

## Delivery order

Parity work follows dependency order: timer interrupts and preemption;
ext2 deletion and full block traversal; multi-session TCP and REPL commands; input and compositor; apps;
audio and image APIs; chipset laboratory; SMP; x86_64 boot; then parity-level
automation and teaching examples. Each row moves to complete only when a
bare-metal integration test covers the corresponding behavior.
