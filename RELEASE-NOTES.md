# RubyOS v0.2.1

## Ruby deserves a first checkout that actually works

This patch release makes recursive cloning and SDL prerequisites explicit,
and tells an incomplete checkout how to initialize its shared service.
Headless desktop tests now set the service's actual `REMOTEOS_SDL_MODE`
variable. A lovingly named variable that nobody reads is not configuration.

RubyOS pins RemoteOS-SDL 0.1.1, aligned with PythonOS 0.4.1. Protocol v2 and
Ruby's class hierarchy, Fibers, live editing, introspection and bare-metal TCP
desktop remain unchanged. No new Ruby VM or runtime is quietly substituted:
CRuby 4.0.6 is still built from source, never taken from old system packages.

## Release media and validation

Linux ARM64 and macOS ARM64 bundles include the private Ruby runtime and native
SDL service. The Linux bundle also contains ARM64 ELF variants and x86_64 ISO
variants. DGX Spark passed the complete Linux parity gate, including networking,
storage, native TCP desktop, input, audio, SMP and debugger checks. An extracted
bundle ran with its relocated Ruby runtime.

The release script requires green Linux and macOS CI, verifies both bundles'
checksums, and publishes the CI-produced artifacts. Host SDL dependencies are
still required; WSL2/WSLg remains unverified. The HTTP service is Rack-shaped,
not a claim that Rails boots today, and remote protocol v2 still needs a
trusted network or authenticated tunnel.

## Executive summary

A cleaner installation, correct headless tests, and the same intensely Ruby
system sharing one host service with PythonOS. Less setup archaeology, more
objects worth inspecting.

[RubyOS v0.2.1](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.2.1)
