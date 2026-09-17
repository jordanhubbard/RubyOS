# Changelog

All notable RubyOS changes are documented here.

## [Unreleased]

- Add bounded host-to-VFS file drops and VFS-to-host exports to Files and the
  shared Open/Save dialogs, with collision-safe names, partial-import cleanup,
  host-policy export paths, and ARM64/x86_64 frozen-guest acceptance.
- Add five interactive Ruby-native graphical demos: Hash-tallied Life,
  Complex Mandelbrot exploration, range-mapped Spirograph, pointer-driven Paint,
  and an immutable-Data lazy starfield, backed by revision-cached bitmaps and
  per-window animation ticks.

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
