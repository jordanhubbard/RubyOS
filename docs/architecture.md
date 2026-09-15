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

1. **Source runtime:** source-built CRuby runs the hosted model and tests.
2. **Freestanding runtime:** ARM64 and x86_64 static CRuby enter Prism and the
   embedded kernel with no Linux interpreter or system Ruby dependency.
3. **Kernel substrate:** exceptions, 100 Hz timers, TLS, allocation, DMA, and
   serial diagnostics are live on both architectures.
4. **Ruby kernel:** Fibers, task lifecycle, devices/drivers, memory, VFS/ext2,
   and network protocols are Ruby objects covered on bare metal.
5. **Desktop and media:** Ruby drives the SDL companion, compositor, apps,
   games, chipset laboratory, image/font APIs, canonical input, and PCM audio.
6. **Native devices:** ARM VirtIO and x86 PS/2/HDA paths cross real QEMU device
   queues and DMA rather than hosted substitutes.
7. **Concurrency:** PSCI and APIC bring all requested CPUs online. CRuby stays
   on its GVL-owning bootstrap processor; Ruby dispatches explicitly C-safe
   hash work to native AP mailboxes.
8. **Debug and automation:** one manifest describes serial, QMP, GDB-remote,
   symbols, desktop logs, and captures; `make parity` exercises the complete
   hosted and native behavior matrix.

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

## Deliberate non-goals

- system Ruby packages
- mruby as a substitute for current CRuby
- YJIT or ZJIT
- arbitrary native gems or dynamic loading
- POSIX process compatibility
- running CRuby VM code concurrently outside its GVL
- production isolation via experimental Ruby Box
