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

The everyday guest commands currently target ARM64 on every host. Native
x86_64 boot, runtime, input, audio, and SMP probes remain available, but
x86_64 does not yet have the equivalent native-TCP interactive desktop.
The ARM64 Docker builder requires ARM execution or emulation on x86 hosts.
This is a current implementation boundary, not a Ruby language restriction.

Linux ARM64 bundles include the new persistent desktop ELF alongside the
existing ARM64 images and x86_64 ISO variants. macOS ARM64 bundles remain
hosted-runtime packages, not proof of macOS bare-metal guest parity.
CRuby 4.0.6 is still built privately from source; RemoteOS-SDL remains 0.1.1.

Lifecycle regression tests exercise the real console, a persistent headless
desktop, duplicate rejection, and scoped shutdown. The release workflow
requires local Linux validation and green Linux/macOS CI, then checks and
publishes the CI-produced bundles. Host SDL dependencies remain required;
WSL2/WSLg is not claimed as verified.

## Executive summary

Fewer commands to learn, a desktop that stays, and cleanup that remembers
how long Ruby took to compile. An outrageous outbreak of approachability.

[RubyOS v0.2.2](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.2.2)
