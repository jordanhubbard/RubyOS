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
| Scheduler | cooperative asyncio tasks, timer accounting, gather/timeouts, Queue/Event/Lock/Semaphore, kill/reap lifecycle | cooperative Ruby Fibers with PIDs, per-task ticks, timed deadlines, join/gather and monotonic timeouts, bounded Enumerable channels, events, block-scoped semaphores and task groups, kill/zombie-style completion, explicit reap, and auto-reap | Complete |
| Interactive shell | serial and multi-session TCP REPL, persistent history, multiline evaluation, completion, cwd-aware file commands, editor, transfers, system/network status, and public desktop/example discovery | shared serial/TCP command processor with private bindings and shared VFS/kernel objects; syntax-aware multiline Ruby, command/path/method completion, VFS-persistent GUI history, `pwd`/`cd`/`cat`/`cp`/`mv`/`run`, streaming `ftp`, `sysinfo`/`netstat`, GUI editor launch, and public `desktop`, `apps`, `examples`, and `example NAME` commands | Complete |
| Device model | buses and typed drivers | enumerable discovery buses, platform/PCI device hierarchy, typed MMIO/port/IRQ resources, specificity-ranked driver DSL, probe/remove lifecycle, lookup, and topology | Complete |
| Memory | physical allocator, DMA, mmap, heap metrics | reclaimable Ruby page-frame manager over the freestanding buddy heap, aligned DMA, mmap shim, and live heap metrics on ARM64/x86_64 | Complete |
| Storage | VFS, tmpfs, ext2, mounted persistent `/home` | Ruby VFS/tmpfs plus writable ext2 over bare-metal VirtIO block, with sparse files, arbitrary truncate, double-indirect traversal, create, unlink, and rmdir | Complete |
| Network | VirtIO net, Ethernet, ARP, IPv4, ICMP, UDP, TCP, DHCP, DNS | bare-metal Ruby VirtIO net, DHCP, ARP, IPv4/ICMP, UDP, DNS, TCP client/server, concurrent REPL sessions | Complete |
| Remote display | RemoteOS-SDL v2 over bare-metal TCP/UART | shared service over hosted TCP, VirtIO console, and RubyOS-native bare-metal TCP | Complete |
| GUI API | SDL-compatible surfaces, events, images, fonts, menus, scrolling, resizing, drag/drop, clipboard | public backend-neutral `RubyOS::App` Canvas/lifecycle/input/audio API plus Ruby `Surface`, owned SDL_ttf `Font`, focusable widgets, bounded labels, scrollable text views, caret-aware multiline editing with keyboard/pointer selection, shared guest clipboard, editor-specific character/word/sentence/paragraph/page/buffer command composition, wheel-scrollable lists and text, pointer-captured guest file drags with visible drop feedback, routed host-file drops, declarative edge anchors, resizable windows, close hooks, meters, app menus, keyboard/pointer dispatch, decoded-surface composition, revision-tracked bitmaps, and per-window animation ticks | Complete |
| Desktop | compositor, windows, app-aware menu bar, dynamic dock, wallpaper, shortcuts, context menus | 1024x768 Ruby compositor with focus/z-order, close/minimize/drag/resize, responsive anchored windows, app-aware menus, desktop/window/text context menus, versioned VFS-persistent shortcuts and dock pins, transient running-app dock entries, wallpaper, status bar, and catalog launcher | Complete |
| Apps | terminal, live editor, files, image viewer, monitor, clock, settings, keybindings, polished shared choosers | About, persistent-history/scrollback Terminal, transactional Live Editor with explicit save/dirty/cancel state, composable navigation commands and shared VFS Open/Save As dialog, navigable Files, VFS-backed BMP/PNG/JPEG/PPM Image Viewer, live System Monitor, Clock, Settings, Keybindings, drill-down Ruby Inspector, two-program timeline-driven Media Workbench, and metadata-driven Launcher; Files and dialogs stream bounded host imports/exports; F5 opens archived built-in source in a writable overlay and atomically replaces the validated Ruby application class | Complete |
| Demos and games | fifteen graphical/audio demos and arcade games | Thirteen Ruby-centric demos span Enumerable, Fiber, pattern matching, Life, Complex/Mandelbrot, Spirograph, Paint, immutable-Data starfield and rain, Plasma, Event Scope, Sprite Layers, and Tone Lab; five tick-driven, shaded high-resolution and PCM-audible games cover Invaders, Snake, Maze, Raiders, and Defender | Complete (13 demos, 5 games) |
| Input | PS/2 and VirtIO input, canonical event queue, configurable persistent desktop shortcuts | bounded canonical Ruby event queue fed by SDL, native x86 PS/2 keyboard/mouse, ARM64 VirtIO keyboard/mouse, normalized SDL modifiers/function keys, and a live-rebindable keymap persisted through the VFS | Complete |
| Audio | Intel HDA/VirtIO/bridge mixer and sound API | Ruby PCM/waveform mixer, bare-metal SDL bridge, native ARM64 VirtIO Sound, and native x86_64 Intel HDA DMA | Complete |
| Images | PNG/JPEG decoding and viewer | Ruby remote surfaces, raw upload, bare-metal PNG/JPEG decode/blit, and Image Viewer | Complete |
| Concurrency | ARM64/x86 SMP, pthread substrate, no-GIL workers | ARM64 PSCI and x86 INIT/SIPI AP bring-up with C-safe native worker mailboxes exposed through Ruby while CRuby remains GVL-safe on the BSP | Complete |
| Debug/automation | QMP/native debug, captures, performance metrics, desktop golden coverage | serial/QMP/GDB-remote, captures, object graphs, class/Fiber/driver reflection, guest timing and shared-service telemetry; architecture-specific frozen-guest tile-hash goldens cover every catalog entry plus guest file dragging and media wipes and reject missing/stale baselines | Complete |
| Web serving | no bundled HTTP application surface beyond general network services | Rack-shaped request environment/router/response served and acceptance-tested through RubyOS's bare-metal TCP stack | Complete (RubyOS exceeds baseline) |
| Teaching examples | categorized start-here, concurrency, storage, networking, graphics/chipset/SDL, audio, and internals lessons | eleven metadata-driven tracks and eighteen frozen, VFS-readable Ruby lessons cover start-here, modern language idioms, structured cooperative/native concurrency, storage, typed networking, graphics, audio, Rack-shaped web composition, internals, demos, and games; the host runs every lesson and ARM64/x86_64 frozen guests prove public discovery, execution, and guide access | Complete |

## Breadth result

The current PythonOS behavior baseline is covered. `Complete` still means an
independently exercised counterpart, not merely a class with a familiar name:
both frozen guest architectures execute the public shell and curriculum, open
and render every catalog entry, and capture real file-drag and media-transition
interactions. Host clipboard synchronization and still deeper per-app scripted
journeys remain worthwhile protocol and quality improvements, but they extend
rather than block the measured PythonOS parity boundary.

## Delivery order

1. Keep the metadata-driven catalog and public example surface reachable from
   hosted Ruby, serial/TCP shells, and the graphical desktop.
2. Keep shared desktop primitives coherent before multiplying bespoke apps,
   especially interaction polish shared by every application.
3. Grow Ruby-native demos around Enumerable, Fiber, pattern matching,
   metaprogramming, refinements, object graphs, Rack-style composition, and
   live class replacement while matching PythonOS's graphical breadth.
4. Continue deepening cross-architecture interaction sequences beyond the
   parity gate as ongoing quality work.
