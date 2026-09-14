# RubyOS architecture and bring-up gates

## Principle

Assembly establishes the CPU execution environment. A small freestanding C
substrate supplies allocation, stack discovery, interrupts, and the CRuby
embedding boundary. After the supported `ruby_setup` plus `ruby_options`
initialization sequence, Ruby is the kernel runtime rather than a userspace
program.

```text
firmware/bootloader -> assembly/C -> static CRuby -> RubyOS::Kernel.boot
                                      |
                     RubyOS::HAL built-in C extension
                                      |
       scheduler / devices / VFS / network / GUI / applications
                                      |
      VirtIO console or TCP bridge -> host SDL window/audio/input
```

## Source policy

`config/ruby.mk` pins the newest validated stable CRuby release. The build
downloads its official source archive, verifies SHA-256, and bootstraps it
without any installed Ruby interpreter. JITs are disabled during bring-up.
They add executable-memory and Rust-runtime concerns without changing the
interpreter semantics RubyOS needs to validate.

## What carries over from PythonOS

- x86_64 GRUB/long-mode bootstrap, linker layout, serial, timer, and interrupt
  concepts
- a freestanding libc and allocator, adapted to symbols CRuby actually imports
- a small built-in `RubyOS::HAL` extension for port I/O, MMIO, DMA, interrupt
  routing, performance counters, and raw UART transport
- the version-1 bridge protocol: a four-byte network-order JSON length,
  optional binary trailer, capability handshake, batches, and ordered one-way
  frames
- compositor behavior and the host SDL companion's operation vocabulary

The Ruby implementation is intentionally not a transliteration. Blocks,
mixins, `Enumerable`, `Fiber`, `Data`, pattern matching, refinements, and DSLs
should define its public shape.

## Gates

1. **Source runtime (complete):** source-built CRuby runs the kernel model and
   tests.
2. **Freestanding link probe (complete):** build `libruby-static.a` against a
   measured RubyOS libc and evaluate embedded source without a Linux ELF
   interpreter.
3. **Serial Ruby kernel (booting):** QEMU enters CRuby 4.0.6, initializes Prism,
   and prints through the RubyOS serial substrate. GC stress and a richer HAL
   remain.
4. **Fiber kernel (cooperative slice complete):** Ruby Fibers schedule and
   yield on the freestanding ARM64 runtime. Timer-driven ticks, exception
   containment, and task introspection remain.
5. **Remote desktop (bare-metal slice complete):** hosted and freestanding Ruby
   drive a forked SDL2 companion through `Transport`, `Client`, `Surface`, and
   `RemoteDesktop` objects. The ARM64 kernel's transport and VirtQueue logic
   are Ruby over five MMIO/DMA HAL primitives.
6. **Ruby-native desktop:** compositor, IRB-like terminal, object browser,
   source workspace, live method replacement, and app DSL.
7. **Storage/network:** port VirtIO, VFS, TCP, and remote REPL as Ruby objects.
8. **SMP research:** only after the single-core system is stable, evaluate
   CRuby Threads/Ractors and the platform hooks they require.

## Instruction sequence policy

Ruby VM instruction-sequence binaries are useful as a later build artifact,
but they are MRI-, version-, machine-, and architecture-dependent and their
loader does not verify hostile or corrupted input. Early kernels embed trusted
Ruby source and compile it with the exact linked interpreter. A later freezer
may emit ISeq blobs only from the same pinned target build and must retain the
source for inspection and recovery.

## Static embedding finding

The source build already emits `libruby-static.a`, and the hosted C probe
successfully enters CRuby with `ruby_sysinit`, `RUBY_INIT_STACK`, and
`ruby_setup`. Kernel links must retain all VM initialization objects (the
hosted probe uses linker whole-archive mode). Ruby exceptions must only cross
C through protected calls: a direct C API lookup that raises before an EC tag
is established aborts the VM instead of behaving like a Ruby-level rescue.

The ARM64 cross-build now emits the full CRuby 4.0.6 static archive for
`aarch64-unknown-none`. Configure results that would falsely retain Linux APIs
are explicitly removed, and the final kernel links against a curated RubyOS
libc/HAL plus `libgcc`, with no glibc or ELF interpreter. The platform supplies
TLS, allocation, memory mapping, minimal pthread synchronization, time,
stdio, and processless syscall semantics. In particular, Ruby 4's dynamic
`PTHREAD_STACK_MIN` query must return a real value before Fiber stack pools are
initialized.

## Explicit non-goals for the first bare-metal milestone

- system Ruby packages
- mruby as a substitute for current CRuby
- YJIT or ZJIT
- arbitrary native gems or dynamic loading
- POSIX process compatibility
- parallel Ractors or production isolation via experimental Ruby Box
