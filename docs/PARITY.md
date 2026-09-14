# PythonOS feature parity

This ledger compares behavior, not implementation language. RubyOS should feel
native to Ruby while offering the same useful system surfaces as PythonOS.

| Area | PythonOS baseline | RubyOS evidence | Status |
|---|---|---|---|
| Source-built language runtime | Cross-built CPython | CRuby 4.0.6 with Prism and native Fiber context backends, cross-built as static ARM64 and x86_64 kernels | Complete |
| Bare-metal boot | x86_64 and ARM64, exceptions, timers | ARM64 EL1/FPU/TLS/exceptions/GICv2-v3 timer plus x86_64 Multiboot2/long-mode/SSE/TLS/IDT/PIT | Complete |
| Scheduler | asyncio tasks, timers, AP workers | Cooperative Ruby Fibers, timed sleep/deadline queue, monotonic `Timekeeper` | Partial |
| Interactive shell | serial and multi-session TCP REPL, commands, editor | shared serial/TCP command processor, simultaneous TCP sessions with private bindings and shared VFS/kernel objects, GUI editor | Complete |
| Device model | buses and typed drivers | `Bus`, `Device`, `Driver` mixin | Partial |
| Memory | physical allocator, DMA, mmap, heap metrics | reclaimable Ruby page-frame manager over the freestanding buddy heap, aligned DMA, mmap shim, and live heap metrics on ARM64/x86_64 | Complete |
| Storage | VFS, tmpfs, ext2, mounted persistent `/home` | Ruby VFS/tmpfs plus writable ext2 over bare-metal VirtIO block, with sparse files, arbitrary truncate, double-indirect traversal, create, unlink, and rmdir | Complete |
| Network | VirtIO net, Ethernet, ARP, IPv4, ICMP, UDP, TCP, DHCP, DNS | bare-metal Ruby VirtIO net, DHCP, ARP, IPv4/ICMP, UDP, DNS, TCP client/server, concurrent REPL sessions | Complete |
| Remote display | UART/VirtIO/TCP protocol-v1 SDL companion | hosted TCP and bare-metal VirtIO console | Complete |
| GUI API | SDL-compatible surfaces, events, images, fonts | Ruby `Surface`, owned SDL_ttf `Font`, and widget hierarchy with focused keyboard/text dispatch | Complete |
| Desktop | compositor, windows, menu bar, dock, wallpaper, shortcuts | Ruby compositor with focus/z-order, close/minimize/drag, patterned wallpaper, shortcuts, menu bar, and dock | Complete |
| Apps | terminal, editor, files, image viewer, monitor, clock, settings | About, interactive Terminal, VFS Editor, Files, Image Viewer, System Monitor, Clock, Settings | Complete |
| Demos and games | graphics/audio demos and arcade games | Ruby Chipset Workbench desktop demo | Partial |
| Input | PS/2 and VirtIO input, canonical event queue | SDL mouse, key, and UTF-8 text events routed through Ruby compositor focus and widgets | Partial |
| Audio | AC97/Intel HDA/bridge mixer and sound API | Ruby PCM/waveform mixer and bare-metal SDL audio bridge | Partial |
| Images | PNG/JPEG decoding and viewer | Ruby remote surfaces, raw upload, bare-metal PNG/JPEG decode/blit, and Image Viewer | Complete |
| Chipset laboratory | display lists, copper/blitter/sprites/audio | Ruby playfields, Copper commands, Blitter, Sprite, raster preview | Partial |
| Concurrency | ARM64/x86 SMP, pthread substrate, no-GIL workers | single-core pthread compatibility | Missing |
| Debug/automation | QMP/native debug, captures, performance metrics | deterministic QEMU smokes and SDL captures | Partial |
| Teaching examples | curated storage/network/graphics/audio/internals lessons | executable Ruby lessons for storage, networking, graphics, audio, internals, plus remote desktop | Complete |

## Delivery order

Parity work follows dependency order: scheduler preemption;
native input paths; audio devices; chipset depth; SMP; then parity-level
automation and teaching examples. Each row moves to complete only when a
bare-metal integration test covers the corresponding behavior.
