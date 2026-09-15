# RubyOS v0.2.2

## An operating system, now with commands humans can remember

RubyOS has achieved the previously unimaginable: `make`, `make run`,
`make run-gui`, and `make stop`. The specialized targets still exist, but
memorizing the entire bring-up history is no longer an entrance examination.
`make help` introduces the everyday commands; the advanced build guide keeps
the architecture and device experiments available to their devoted audience.

The desktop now stays open. This astonishing innovation replaces the smoke
test's scripted visit with a persistent, interactive RemoteOS-SDL session.
Terminal, Files, Inspector, Editor, games, and the other Ruby applications
share the existing compositor and native TCP transport.

A Ruby process supervisor owns each checkout's console or desktop session.
It rejects duplicate launches, coordinates shutdown, and stops its own child
processes. Stopping your OS need not involve hunting unrelated processes
with a particularly optimistic kill command.

`make clean` preserves the expensive source-built Ruby caches and persistent
disk. `make cleanall` removes build caches when you actually mean it.
`make package` builds local release media; it does not publish a release.

## Platforms and validation

The everyday commands now select the host CPU, with `TARGET_ARCH=arm64` or
`TARGET_ARCH=x86_64` overrides. x86_64 gains the real console, writable ext2,
DHCP/DNS/TCP, HTTP and persistent native-TCP desktop through modern VirtIO
PCI. The same Ruby network and filesystem code serves both architectures.
The Docker builder runs natively on either host CPU. Owning an Intel machine
no longer enrolls you in an unsolicited ARM emulation appreciation course.

The broader desktop gate also caught an x86 libc rounding routine that
compiled into an infinite self-jump. It now rounds numbers instead of
contemplating them forever, with guest rounding and audio-synthesis tests.

Linux ARM64 and x86_64 bundles include persistent desktop media alongside
the full ARM64 ELF and x86_64 ISO variants. macOS ARM64 bundles remain
hosted-runtime packages, not proof of macOS bare-metal guest parity.
CRuby 4.0.6 is still built privately from source; RemoteOS-SDL remains 0.1.1.

Lifecycle regression tests exercise the real console, a persistent headless
desktop, duplicate rejection, and scoped shutdown. The release workflow
requires local Linux validation and green ARM64 Linux, x86_64 Linux and macOS
CI, then checks and
publishes the CI-produced bundles. Host SDL dependencies remain required;
WSL2/WSLg is not claimed as verified.

## Executive summary

Fewer commands to learn, a desktop that stays, and cleanup that remembers
how long Ruby took to compile. An outrageous outbreak of approachability.

[RubyOS v0.2.2](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.2.2)
