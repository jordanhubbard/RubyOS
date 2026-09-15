# Changelog

All notable RubyOS changes are documented here.

## [Unreleased]

## [0.2.1] - 2026-09-15

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
