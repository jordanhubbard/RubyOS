# PythonOS feature parity

This ledger compares behavior, not implementation language. RubyOS should feel
native to Ruby while offering the same useful system surfaces as PythonOS.

The console, writable ext2, DHCP/DNS/TCP, HTTP and native-TCP desktop gates
run on both ARM64 and x86_64 guests. Their shared Ruby drivers use MMIO and
modern PCI transports respectively. Public `make` commands select either
architecture; Linux CI builds and packages on both host CPUs. The optional
serial desktop/debug harness remains ARM-specific. These are QEMU platform
claims, not certification for arbitrary physical hardware.

| Area | PythonOS baseline | RubyOS evidence | Status |
|---|---|---|---|
| Source-built language runtime | Cross-built CPython | CRuby 4.0.6 with Prism and native Fiber context backends, cross-built as static ARM64 and x86_64 kernels | Complete |
| Bare-metal boot | x86_64 and ARM64, exceptions, timers | ARM64 EL1/FPU/TLS/exceptions/GICv2-v3 timer plus x86_64 Multiboot2/long-mode/SSE/TLS/IDT/PIT | Complete |
| Scheduler | cooperative asyncio tasks, timer accounting, kill/reap lifecycle | cooperative Ruby Fibers with PIDs, per-task ticks, timed deadlines, kill/zombie-style completion, explicit reap, and auto-reap | Complete |
| Interactive shell | serial and multi-session TCP REPL, commands, editor | shared serial/TCP command processor, simultaneous TCP sessions with private bindings and shared VFS/kernel objects, GUI editor | Complete |
| Device model | buses and typed drivers | enumerable discovery buses, platform/PCI device hierarchy, typed MMIO/port/IRQ resources, specificity-ranked driver DSL, probe/remove lifecycle, lookup, and topology | Complete |
| Memory | physical allocator, DMA, mmap, heap metrics | reclaimable Ruby page-frame manager over the freestanding buddy heap, aligned DMA, mmap shim, and live heap metrics on ARM64/x86_64 | Complete |
| Storage | VFS, tmpfs, ext2, mounted persistent `/home` | Ruby VFS/tmpfs plus writable ext2 over bare-metal VirtIO block, with sparse files, arbitrary truncate, double-indirect traversal, create, unlink, and rmdir | Complete |
| Network | VirtIO net, Ethernet, ARP, IPv4, ICMP, UDP, TCP, DHCP, DNS | bare-metal Ruby VirtIO net, DHCP, ARP, IPv4/ICMP, UDP, DNS, TCP client/server, concurrent REPL sessions | Complete |
| Remote display | RemoteOS-SDL v2 over bare-metal TCP/UART | shared service over hosted TCP, VirtIO console, and RubyOS-native bare-metal TCP | Complete |
| GUI API | SDL-compatible surfaces, events, images, fonts | Ruby `Surface`, owned SDL_ttf `Font`, and widget hierarchy with focused keyboard/text dispatch | Complete |
| Desktop | compositor, windows, menu bar, dock, wallpaper, shortcuts | Ruby compositor with focus/z-order, close/minimize/drag, patterned wallpaper, shortcuts, menu bar, and dock | Complete |
| Apps | terminal, live editor, files, image viewer, monitor, clock, settings | About, Terminal, transactional Live Editor, Files, Image Viewer, Monitor, Clock, Settings, Ruby Inspector, Live Ruby | Complete |
| Demos and games | graphics/audio demos and arcade games | graphics/audio lessons plus interactive Ruby Invaders and Snake desktop games with input, animation, collision, scoring, sound cues, and bitmap rendering | Complete |
| Input | PS/2 and VirtIO input, canonical event queue | bounded canonical Ruby event queue fed by SDL, native x86 PS/2 keyboard/mouse, and ARM64 VirtIO keyboard/mouse, all polled at CRuby-safe points | Complete |
| Audio | Intel HDA/VirtIO/bridge mixer and sound API | Ruby PCM/waveform mixer, bare-metal SDL bridge, native ARM64 VirtIO Sound, and native x86_64 Intel HDA DMA | Complete |
| Images | PNG/JPEG decoding and viewer | Ruby remote surfaces, raw upload, bare-metal PNG/JPEG decode/blit, and Image Viewer | Complete |
| Concurrency | ARM64/x86 SMP, pthread substrate, no-GIL workers | ARM64 PSCI and x86 INIT/SIPI AP bring-up with C-safe native worker mailboxes exposed through Ruby while CRuby remains GVL-safe on the BSP | Complete |
| Debug/automation | QMP/native debug, captures, performance metrics | serial/QMP/GDB-remote, captures, object graphs, class/Fiber/driver reflection, guest timing and shared-service telemetry | Complete |
| Web serving | Python network services | Rack-shaped request environment/router/response served by RubyOS's bare-metal TCP stack | Foundation complete |
| Teaching examples | curated storage/network/graphics/audio/internals lessons | executable Ruby lessons for storage, networking, graphics, audio, internals, live Ruby, object graphs, web, and remote desktop | Complete |

## Delivery order

Every PythonOS behavior row now has a RubyOS implementation and integration
evidence. `make parity` runs the hosted contracts and the ARM64/x86_64 native
matrix; future changes should keep the corresponding bare-metal gate green.
