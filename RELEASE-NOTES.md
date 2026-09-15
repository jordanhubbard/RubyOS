# RubyOS v0.2.0

## Ruby has stopped sharing its SDL homework

RubyOS and PythonOS now speak one deliberately breaking RemoteOS protocol v2
to one shared RemoteOS-SDL service. The copied C companion is gone. Ruby queues
response-free drawing operations as a bounded render batch, then
`frame.commit` presents and brings input home in the same round trip. The host
reports wire volume, dropped events, audio depth, and per-operation SDL time,
which is rather more actionable than staring sternly at a window.

More importantly, this path runs from bare metal. CRuby 4.0.6 acquires DHCP
through RubyOS's VirtIO NIC, accepts the display service through RubyOS's TCP
listener, segments the stream below Ethernet MTU, and drives the entire desktop
without a QEMU character-device shortcut. The old VirtIO-console route remains
an independently useful device path, not a compatibility facade.

## The live system is aggressively Ruby

The desktop now includes Live Ruby and Ruby Inspector. Application source lives
in the RubyOS VFS, compiles into an anonymous Module, and replaces the registry
entry only after evaluation succeeds. A syntax error or failed evaluation
leaves the running application intact. `RubyOS::Live::ClassEditor` similarly
patches real instance methods and restores their prior definitions if the
transaction raises.

The introspection API reports bounded, cycle-aware object graphs; class
ancestors, methods, and constants; heap leaders; scheduler Fibers; and live
device/driver bindings. This is not a generic remote-debug facade painted red.
It is Ruby's object model used as an operating-system workbench.

## A web server, with honesty included

RubyOS now parses HTTP, routes with blocks, creates a Rack-shaped environment,
and serves `[status, headers, body]` responses from its bare-metal TCP stack.
The release gate boots the kernel and curls it through QEMU forwarding.

That is a meaningful path toward Rack and, eventually, Rails. It is not a claim
that Rails runs today. Rails still expects a much larger stdlib and gem surface,
stronger socket/thread contracts, persistent services, databases, clocks, and
native extensions. RubyOS will earn those layers instead of adding a logo and
hoping nobody asks for Active Record.

## ISeq: cache, not constitution

The source-built Ruby can freeze and reload instruction sequences, and the new
tool records engine, version, revision, platform, source hash, and binary hash.
MRI itself says those binaries are not portable and its loader does not verify
hostile input. Our build interpreter is `aarch64-linux`; the kernel is
`aarch64-none`. Therefore source remains the boot format and ISeq remains an
exact-build, trusted cache experiment until the target itself can produce it.

## Builds and artifacts

- Linux CI builds source Ruby and executes hosted plus ARM64/x86_64 bare-metal
  parity, including native-TCP desktop and HTTP server gates.
- macOS CI builds Ruby from source, runs the hosted/runtime/RemoteOS suites, and
  emits its own release bundle.
- Windows continues through the Linux contract under WSL2.
- Bundles include the source-built Ruby runtime and canonical `remoteos-sdl`
  binary, never a distribution Ruby package.

## Executive summary

RubyOS 0.2.0 has one shared, measured host-device boundary; a native TCP remote
desktop; live Module/class surgery with rollback; an object/Fiber/driver
inspector; and an HTTP server running where an operating system normally lives.
It remains source-built CRuby all the way down, because ancient package managers
have contributed enough to this experiment already.

[Download RubyOS v0.2.0](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.2.0)
