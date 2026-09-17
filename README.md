# RubyOS

RubyOS explores the same inversion as PythonOS with Ruby at its center: a
minimal assembly/C substrate starts CRuby, then Ruby objects own the kernel,
drivers, scheduler, filesystem, network stack, desktop, and applications.

This project builds Ruby from the official upstream source archive. It does
not use a system Ruby package, a system `ruby` executable, or a system
`libruby`. The pinned version and checksum live in `config/ruby.mk`.

See [the current release notes](RELEASE-NOTES.md), [changelog](CHANGELOG.md),
and [the three-repository alignment guide](docs/remoteos-alignment.md).

## Getting started

```sh
git clone https://github.com/jordanhubbard/RubyOS.git
cd RubyOS
make install
```

`make install` is the supported bootstrap on ARM64 and x86_64 macOS or
Debian/Ubuntu Linux. It installs Homebrew packages on macOS, apt packages on
Linux, initializes submodules, starts Docker when possible, and builds the
native-host cross-toolchain container. Xcode command-line tools are required
on macOS.

On Windows, run `make install` inside an ARM64 or x86_64 WSL2 Debian/Ubuntu
distribution. Docker Desktop WSL integration or a running in-WSL Docker
service is required; visible SDL windows also require WSLg.

After installation, use the same `make`, `make run`, and `make run-gui` entry
points below. `make build-macos` remains a hosted-only development suite.

## What runs today

RubyOS carries the PythonOS behavior surface in Ruby on source-built CRuby:

- Ruby 4.0.6 bootstrapped and installed privately in `build/host-ruby`
- the same CRuby source cross-built as freestanding ARM64 and x86_64 static runtimes
- a cooperative `Fiber` kernel scheduler with timed deadlines and task lifecycle accounting
- ARM generic-counter monotonic time, 100 Hz GICv2/v3 timer IRQs, sleeping, and a Ruby session clock
- a Ruby VFS/tmpfs with mount routing and file-descriptor semantics
- Ruby-native Ethernet, ARP, IPv4, ICMP, and UDP packet objects
- an enumerable device hierarchy, typed resources, and a matching/priority driver DSL
- reclaimable page-frame memory backed by the native allocator
- writable ext2, VirtIO block/network, DHCP/DNS/TCP, and concurrent TCP Ruby consoles
- a Ruby-native `Element -> View -> Container/Label -> Button` GUI hierarchy
- a Ruby compositor with focus/z-order, windows, menu bar, dock, and system apps
- the shared RemoteOS-SDL v2 service plus an idiomatic Ruby
  `Transport -> Client -> Surface -> RemoteDesktop` hierarchy
- strict, jointly versioned RemoteOS framing with bounded render batches,
  combined present/input commits, and service telemetry
- transactional live application reloads and class patches, plus object graph,
  Fiber, class, heap, device, and driver reflection
- a Rack-shaped HTTP server that serves real requests from the bare-metal stack
- native PS/2 and VirtIO input, x86 HDA and ARM VirtIO Sound
- ARM PSCI and x86 APIC multi-core bring-up with GVL-safe native worker mailboxes
- a unified serial, QMP, GDB-remote, capture, and performance-debug plane
- QEMU kernels that enter CRuby with the RubyOS libc and boot the real Ruby object model

Everyday commands:

```sh
make              # build the bootable Ruby console
make run          # boot it; type Ruby at rubyos>
make run-gui      # open the persistent SDL desktop
make test         # hosted checks + bare-metal console smoke
make test-gui     # headless native-TCP desktop smoke
make stop         # stop this checkout's running session
make help         # show the small public command set
```

At any `rubyos>` prompt, `apps` lists the categorized desktop catalog,
`examples` lists kernel-embedded Ruby lessons, and `example NAME` executes one.
The graphical **Apps** launcher exposes full applications, Ruby-focused demos,
and games without pinning every demo to the dock. Current language labs cover
Enumerable pipelines, Fiber yield/resume choreography, and structural pattern
matching; their underlying examples are readable in `/examples`.
The desktop menu bar is registry-driven and gains commands from the focused
Ruby application. F1 opens the live-rebindable keymap, F2 opens Applications,
F3 opens Terminal, and F4 opens Files; Ctrl-W closes the focused window.
Rebound shortcuts are stored in `/home/.rubyos-keybindings`, restored on the
next desktop session, and can be reset to defaults from the Shortcuts menu.
The editor's File menu uses a shared, keyboard-and-mouse navigable VFS dialog
for Open and Save As. Its multiline Ruby buffer supports caret placement,
Shift/drag selection, vertical/page navigation, wheel scrolling, and guest
clipboard cut/copy/paste through the standard Ctrl+A/C/X/V chords.
Windows resize from their lower-right grip. Anchored Ruby views stretch or
track an edge declaratively, which keeps Files, Terminal, Editor, dialogs,
the application catalog, and Ruby demos usable as their windows change size.
Right-click opens keyboard-navigable context menus: the desktop launches core
apps, windows expose minimize/close, and text fields offer selection-aware
cut/copy/paste actions.
The dock keeps a compact set of core applications, marks running apps, shows
unpinned apps transiently, and persists Keep/Remove choices in
`/home/.rubyos-dock`.

These commands select the host CPU by default: ARM64 on ARM hosts, x86_64 on
Intel/AMD hosts. Use `make run-gui TARGET_ARCH=x86_64` or `TARGET_ARCH=arm64`
to select either guest explicitly. Docker must be running; a native-host
builder image is created automatically if missing. Both cross-compilers run
inside it, so x86 hosts do not need ARM Docker emulation. QEMU emulates the
selected guest when it differs from the host CPU.

`make build-gui` prepares the GUI without starting it. `make package` builds,
tests and packages locally without publishing. `make clean` preserves the
source-built Ruby caches and persistent disk; `make cleanall` also removes
runtime builds and the downloaded archive. Both stop this checkout's session.

The desktop stays open until its window closes, Ctrl-C, or `make stop` in a
second terminal. Guest output is in `build/run/serial.log`. Set
`REMOTEOS_SDL_MODE=headless SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy`
for a hidden desktop. `RUBYOS_REMOTEOS_PORT` selects the local forwarded port
(default 17012). The launcher binds only loopback and does not kill other VMs.

For subsystem probes, source-built runtime tools, cross-architecture tests and
release gates, see [advanced build targets](docs/build-targets.md).

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
Prism, Ruby-defined devices, cooperative Fibers, and native VirtIO devices on
QEMU's `virt` machine.

`make rubyos-x86_64-smoke` independently cross-builds CRuby with its amd64
Fiber coroutine backend, packages a Multiboot2 ELF with GRUB, and boots the
same embedded Ruby kernel under `qemu-system-x86_64`. It provides COM1, static
TLS, SSE, a reclaimable heap, a 100 Hz PIT clock, IDT exception probes, PS/2
input, Intel HDA audio, and APIC multi-core workers.

Both architectures also provide the console, writable ext2 storage,
DHCP/DNS/TCP, HTTP and persistent RemoteOS-SDL desktop. The shared Ruby
network/block drivers use VirtIO MMIO on ARM64 and modern VirtIO PCI on
x86_64; no host networking or filesystem calls replace guest drivers.
Replace `arm64` with `x86_64` in the REPL, storage, network, web and TCP GUI
smoke targets below to exercise the same assertions against the other CPU.

The initial platform libc is adapted from PythonOS and retains its BSD license
in `platform/PYTHONOS-LICENSE`.

## Learn by changing Ruby

`make teaching-examples` runs focused lessons in `examples/` for VFS and file
descriptors, typed network packets, compositor drawing, PCM synthesis, device
binding, Fiber scheduling, live class replacement, bounded object graphs, and
Rack-shaped web apps. They use the private source-built Ruby and the
same classes embedded into the bare-metal kernel, so each example is a small
starting point rather than a parallel mock API.

## SDL remote desktop

`make test-bridge` builds the shared `services/remoteos-sdl/remoteos-sdl` and uses the privately built
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
REMOTEOS_SDL_MODE=interactive \
  services/remoteos-sdl/remoteos-sdl --listen-tcp 127.0.0.1:17010
```

```sh
build/host-ruby/bin/ruby -I kernel examples/remote_desktop.rb
```

The v2 wire protocol is currently unauthenticated and unencrypted. Keep it on
loopback or a trusted private/SSH-forwarded connection.

`make rubyos-arm64-tcp-gui-smoke` proves the preferred bare-metal transport:
RubyOS acquires DHCP through its VirtIO NIC, accepts RemoteOS-SDL on its own TCP
listener, segments the stream below Ethernet MTU, and drives the same desktop
client. VirtIO console remains useful as an independent local device path.

The bare-metal desktop is composed by Ruby objects rather than a fixed bridge
scene. `Compositor` owns window focus and z-order, while `Application`
subclasses build About, Files, interactive Terminal, System Monitor, Clock, and
Settings windows from live kernel state, with VFS-backed Editor and Image
Viewer applications alongside them. Ruby `Surface` objects create, upload,
decode PNG/JPEG through SDL_image,
blit, and destroy remote image resources. Ruby `Font` objects discover, open,
measure, render, and close host SDL_ttf fonts with explicit ownership. SDL mouse events are normalized by the bridge and routed through
Ruby hit testing; keyboard and UTF-8 text events follow window focus into Ruby
widgets, including a live Terminal evaluator and VFS-persisted Editor. The
bare-metal smoke types into Terminal and clicks the dock to launch and focus the
System Monitor. The dock also exposes Ruby Inspector and a Live Ruby app whose
source lives at `/apps/live_hello.rb`; Editor recompiles it in an anonymous
Module and swaps the application only after successful evaluation. Ruby sine
generators and a saturating PCM mixer stream stereo
audio through the same companion. The SDL companion remains a rendering,
input, and audio device.

The Ruby Media Workbench and games use ordinary image objects. The new
[Ruby multimedia framework](docs/multimedia.md) adds scoped SDL resources,
2D scenes, perspective 3D meshes, animation, PCM audio and video decoding.
See that guide for runnable creation/playback examples and current limits.

## Bare-metal Ruby console

`make rubyos-arm64-repl-smoke` builds the console kernel and drives its PL011
input under QEMU. The prompt evaluates ordinary Ruby and provides `help`,
`version`, `devices`, `tasks`, `uptime`, `sleep`, `time`, `ls`, `cat`, and
`write`, `mkdir`, `rm`, and `debug` commands backed by live kernel objects.

`make rubyos-arm64-storage-smoke` adds a generated ext2 disk to QEMU. Ruby
discovers it through a Ruby VirtIO-MMIO block driver, parses ext2 without a C
filesystem library, and mounts its persistent `/home` and `/apps` trees into
the VFS. Files created or replaced from the Ruby shell are allocated and
written back to the disk. File unlink and empty-directory removal reclaim their
ext2 blocks and inodes. Sparse extension, arbitrary shrinking, and writable
double-indirect block traversal are covered by the filesystem checks.

`make rubyos-arm64-network-smoke` attaches QEMU user networking and proves a
Ruby-owned VirtIO-MMIO NIC, ARP resolution, IPv4, and ICMP by receiving an echo
reply from the virtual gateway. It then completes a TCP handshake and payload
round trip to a source-built-Ruby host service. The interface address, gateway,
netmask, DNS server, and lease time come from a Ruby DHCP client. Packet framing,
checksums, DNS compression parsing, and connection sequencing are ordinary Ruby
objects. A host-forwarded connection also exercises the server-side TCP
handshake and evaluates Ruby through the freestanding kernel's TCP REPL. The
REPL demultiplexes simultaneous connections, preserves a private Ruby binding
for each client, and shares the live RubyOS object graph between them.

`make rubyos-arm64-web-smoke` serves an actual HTTP request from that same
bare-metal TCP stack. The application contract is intentionally Rack-shaped:
`call(env)` returns `[status, headers, body]`. This is the honest stepping stone
toward Rack and eventually Rails; Rails itself still needs a substantially
richer stdlib/gem, threading, clock, persistence, socket, and native-extension
surface than RubyOS currently provides.

For an interactive session:

```sh
make rubyos-arm64-repl
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512M \
  -nographic -monitor none -serial stdio \
  -kernel build/baremetal/rubyos-arm64-repl/rubyos.elf
```

## Native debugging and parity automation

`make debug-smoke` launches the ARM64 desktop with independent serial, QMP,
and GDB-remote planes, records `build/rubyos-debug.json`, verifies a native
stop reply, captures the SDL framebuffer, and checks both Ruby-side request
latency and SDL companion service-time metrics. `make debug-session` performs
the same checks and then keeps the VM alive. From another terminal:

```sh
tools/rubyos_debug.py session
tools/rubyos_debug.py serial
tools/rubyos_debug.py qmp status
tools/rubyos_debug.py native
tools/rubyos_debug.py native -- "info registers" "bt"
tools/rubyos_debug.py capture
```

`make parity` is the release-style gate. It runs hosted object-model tests and
teaching examples, then the storage, network, desktop, console, input, audio,
SMP, and debug smokes on both native architectures where applicable.

## CI, release builds, and Windows

GitHub Actions runs `release-linux` on ARM64 and x86_64 Ubuntu runners and
`release-macos` on an Apple Silicon runner. The Linux gate executes the full
QEMU parity matrix and packages ARM64 ELFs, x86_64 ISOs, the ext2 image,
RemoteOS-SDL, and source-built Ruby runtime. The macOS gate runs the hosted kernel,
object, lesson, network, and SDL suites before packaging its source-built Ruby
and the same RemoteOS-SDL service.

```sh
make docker-build      # Linux freestanding builder
make build-linux
make release-linux
make build-macos
make release-macos
make validate-release
```

Tagged releases are published by `scripts/release.sh` only after all three host
jobs pass, and use the bundles produced by CI. Windows uses the Linux targets
inside WSL2; RubyOS does not claim a separate native Win32 build.
