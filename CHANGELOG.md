# Changelog

All notable RubyOS changes are documented here.

## [Unreleased]

## [0.4.0] - 2026-09-21

- Render all GUI text through SDL_ttf via `RubyOS::GUI::Text`, caching rendered
  runs host-side, with the embedded 8x8 face as the fallback for a host with no
  usable font. Column arithmetic follows the measured advance instead of an
  assumed 8 pixels, and a proportional face is refused rather than laid out on
  a grid it does not honour. Visual goldens pin the bitmap face so their hashes
  stay host-independent.
- Replace the dock's text labels with centred square icons, a hover label and a
  running-app pip. `RubyOS::GUI::Icons` renders each icon at whatever size the
  dock asks for. Replace the debug-grid wallpaper with a banded gradient.
- Treat the desktop size as a request rather than a constant: adopt the
  framebuffer `display.open` reports, steerable from the host with
  `RUBYOS_DESKTOP_SIZE`. Scale window geometry against a 1024x768 reference,
  capped at 2x. Open the editor, launcher and inspector at sizes that fit their
  contents on a full desktop.
- Raise the `mmap` record table from 128 to 16384 mappings. CRuby's GC takes a
  mapping per heap page, so the table filled after a few megabytes of object
  heap and `mmap` returned `MAP_FAILED` with memory still plentiful, which
  CRuby reports as exhaustion and aborts on. This is why
  `rubyos-arm64-gui-smoke` had been failing.
- Stop the virtio-console transport leaking a DMA buffer per bridge message,
  and move payloads with `memcpy` rather than a Ruby call per byte. arm64 gains
  a bulk DMA primitive; both architectures gain the read direction.
- Pin RemoteOS-SDL 0.3.0.

## [0.3.2] - 2026-09-17 (unreleased; shipped in 0.4.0)

- Match PythonOS's 1024x768 interactive desktop, replace enlarged game pixels
  with shaded high-resolution arcade rendering, and connect all five games to
  audible PCM startup, action, score, rescue, danger, and game-over cues.
- Add the public backend-neutral `RubyOS::App` class library: portable Canvas,
  lifecycle, input, fixed-step Runtime and Audio APIs run unchanged with an
  in-memory/native surface or the optional RemoteOS-SDL backend.

- Complete the PythonOS behavior ledger with a stateful Ruby shell: persistent
  Terminal history, syntax-aware multiline evaluation, command/path/method
  completion, cwd-aware file operations, source execution, system/network
  inspection, desktop/editor launch, and streaming TCP file transfer. Add an
  active TCP client API with FIN-as-EOF semantics and portable-pixmap viewing.
- Add structured Fiber concurrency with join/gather, monotonic timeouts,
  bounded Enumerable channels, events, block-scoped semaphores and task groups;
  the frozen curriculum now runs producer/consumer and coordinated-worker
  examples through those public Ruby APIs on both guest architectures.
- Replace the static Media thumbnail with a Ruby-native two-program studio:
  reusable seekable bitmap wipes, four directions, timeline animation, direct
  cuts, keyboard/menu controls, progress feedback, an SDL audio cue, and
  frozen ARM64/x86_64 interaction captures.
- Add pointer-captured guest file dragging to reusable Ruby `ListView` widgets;
  Files and shared Open/Save dialogs now show a bounded drag badge and export
  only when a file is released on the Export target, with frozen ARM64/x86_64
  acceptance through the real host-policy transfer path.
- Add ARM64 and x86_64 frozen-guest visual baselines for every catalog entry,
  using Ruby BMP parsing and 16-pixel SHA-256 tile comparisons with explicit
  refresh, catalog-membership checks, and a bounded allowance for live views.
- Add focused-window source editing on F5: built-in application source is
  archived into frozen guests, copied to a writable `/apps` overlay, evaluated
  under an isolated Ruby namespace, and transactionally swapped into the live
  registry, dock, and desktop only after successful compilation and validation.
- Add bounded host-to-VFS file drops and VFS-to-host exports to Files and the
  shared Open/Save dialogs, with collision-safe names, partial-import cleanup,
  host-policy export paths, and ARM64/x86_64 frozen-guest acceptance.
- Add five interactive Ruby-native graphical demos: Hash-tallied Life,
  Complex Mandelbrot exploration, range-mapped Spirograph, pointer-driven Paint,
  and an immutable-Data lazy starfield, backed by revision-cached bitmaps and
  per-window animation ticks.
- Replace static desktop diagnostics with a scrollable Ruby `TextView`, bounded
  Terminal scrollback and command history, a tick-driven live System Monitor,
  and a navigable Ruby Inspector for fibers, drivers, heap leaders, object
  graphs, ancestors, methods, and constants.
- Reach the PythonOS catalog breadth count with ten Ruby demos and five games:
  add Enumerable Plasma, pattern-matched Event Scope, Hash/Data Maze, Data
  Raiders, and a circular-world Ruby Defender with radar, abduction, rescue,
  projectiles, and smart bombs. Arcade canvases are now focusable, tick-driven,
  status-bearing, and revision-cached rather than static pixel showcases.
- Cover the remaining media scenarios with immutable-Data Rain, transparent
  Bitmap Sprite Layers, and an interactive Tone Lab for bounded Ruby sine,
  square, triangle, and chord PCM. Replace the placeholder Image Viewer with
  VFS-backed BMP/PNG/JPEG decoding, keyboard/wheel panning, shared Open dialog,
  file-manager routing, and close-safe remote surface ownership.
- Replace Editor autosave with explicit saved/dirty/cancel state and add an
  idiomatic `EditorInput` command object: Ctrl-X save/close composition,
  character/line/word/sentence/paragraph/page/buffer navigation, indentation,
  kill-line, recentering, bound menus, and frozen-guest persistence checks.
- Turn the flat embedded examples into an immutable Ruby curriculum: eleven
  discoverable tracks, seventeen runnable lessons, generated VFS guides and
  readable sources, track-aware shell commands, start-here algorithms,
  cooperative/native concurrency, and host plus ARM64/x86_64 frozen execution.

## [0.3.1] - 2026-09-16

- Add `make install` as the supported self-bootstrap path for ARM64 and x86_64
  macOS, Debian/Ubuntu Linux and Windows WSL2 hosts.
- Install Homebrew or apt dependencies, initialize recursive submodules, start
  Docker where possible and prepare the native-host cross-toolchain image.
- Route container commands through a Linux sudo fallback for newly installed
  Docker services whose group membership is not active in the current shell.
- Identity-map ARM64 MMIO as device memory and RAM as normal write-back memory
  before entering CRuby, fixing alignment faults in valid scalar and SIMD
  accesses during console and desktop boot.
- Exercise the installer matrix in local/release gates and use the public
  bootstrap path in Linux ARM64, Linux x86_64 and macOS CI.
- Keep pointer clicks on text inputs and other non-button views from being
  dispatched as synthetic button events, preventing an interactive desktop
  exception after clicking the Terminal or Editor.
- Make the public GUI supervisor detect fatal guest logs, stop its QEMU and SDL
  children, and exit unsuccessfully instead of appearing to hang forever.

## [0.3.0] - 2026-09-15

- Add block-scoped Ruby SDL resources, capability checks, bounded batching,
  2D scenes, perspective meshes, seekable timelines and a paced Studio loop.
- Add video decode/seek, audio-clocked playback and fixed-step audiovisual
  recording through shared RemoteOS-SDL 0.2.1; include Studio and movie examples.
- Remove the emulated chipset hierarchy and migrate games to plain bitmaps.
- Validate 3D and audiovisual export/playback from ARM64 and x86_64 bare-metal
  guests over native TCP, plus hosted integration in the platform release gate.

## [0.2.2] - 2026-09-15

- Add PythonOS-style everyday make commands, with `help` and a separate
  advanced-targets guide. Bare `make` builds the host-architecture console.
- Add a persistent native-TCP desktop and a Ruby launcher with checkout-local
  start/stop supervision, plus real-console/desktop lifecycle regression tests.
- Keep hosted tests explicit as `test-host`; preserve Ruby caches on `clean`.
- Include the persistent desktop ELF in Linux release bundles.
- Add modern VirtIO PCI transport for x86_64 networking and writable ext2,
  serial REPL input, HTTP and native-TCP desktops using shared Ruby drivers.
- Select either guest with `TARGET_ARCH`; run Docker builders natively on
  ARM64 or x86_64 and require both Linux host architectures in release CI.
- Package x86_64 console, storage, network, web and desktop ISOs; validate
  public command lifecycle and shared feature tests against both guest CPUs.
- Fix recursive x86 libc rounding that hung audio synthesis; add bare-metal
  rounding and waveform regressions and readiness-driven serial tests.
- Check exact native page reclamation without interleaved Ruby VM allocations
  perturbing the boot self-test; retain Ruby frame lifecycle assertions.

## [0.2.1] - 2026-09-15

- Synchronize native input injection with driver readiness, not generic boot.
- Propagate failed CI watches explicitly from the release script.
- Clarify recursive cloning, submodule recovery and SDL prerequisites.
- Set the shared service's actual headless-mode variable in desktop tests.
- Pin RemoteOS-SDL 0.1.1, including corrected package checksums and standalone
  Linux ARM64 release media.
- Validate local Linux ARM64 builds, full parity tests and relocated packages
  on DGX Spark; retain required Linux/macOS hosted release gates.

## [0.2.0] - 2026-09-14

### Added

- RemoteOS-SDL v2 over RubyOS's bare-metal VirtIO TCP stack, including an
  end-to-end desktop gate.
- Transactional live application reloads and rollback-safe runtime method
  patches using real Ruby Modules and classes.
- Bounded object graphs plus live class, heap, Fiber, device, and driver
  introspection, with Ruby Inspector and Live Ruby desktop apps.
- A Rack-shaped HTTP router/server with a real bare-metal request gate.
- Exact-build ISeq cache tooling, validation, and a documented portability
  boundary.
- Live Ruby, object graph, and web teaching lessons.

### Changed

- Removed the forked RubyOS SDL bridge and pinned the shared RemoteOS-SDL
  service as a submodule.
- Upgraded the guest to strict protocol v2, bounded rendering batches,
  `frame.commit`, and unified service telemetry.

## [0.1.0] - 2026-09-14

### Added

- Source-built CRuby 4.0.6 with Prism on hosted, ARM64, and x86_64 targets.
- Ruby-owned scheduling, memory, devices, VFS/ext2, networking, desktop, apps,
  games, input, audio, chipset emulation, and native worker APIs.
- ARM64 VirtIO and x86_64 PS/2, Intel HDA, interrupt, timer, and SMP paths.
- SDL remote desktop with images, fonts, audio, capture, and performance data.
- Unified serial, QMP, GDB-remote, and deterministic parity automation.
- Linux and macOS CI build/release targets, with Windows supported through WSL2.
