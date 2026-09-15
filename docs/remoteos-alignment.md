# PythonOS, RubyOS, and RemoteOS-SDL alignment

The two operating systems now share one host-side device service:
[RemoteOS-SDL](https://github.com/jordanhubbard/RemoteOS-SDL). Each repository
pins it as `services/remoteos-sdl`; neither carries a copied C bridge.

| Concern | PythonOS | RubyOS | RemoteOS-SDL |
|---|---|---|---|
| Language runtime | source-built CPython | source-built CRuby 4.0.6 | no guest runtime |
| Kernel personality | asyncio, Python modules | Fiber, Modules, objects/DSLs | none |
| Scene and apps | Python | Ruby | none |
| Transport | bare-metal TCP or UART | bare-metal TCP, VirtIO console, hosted TCP | TCP or Unix socket |
| Host devices | protocol client | protocol client | SDL display/input/audio/image/font |
| Performance view | guest RPC timing | guest RPC timing | wire counters and SDL service time |

Protocol v2 is deliberately breaking. Both clients send a named `hello`, use
`render.batch` only for response-free draw operations, and use `frame.commit`
to present plus collect input in one round trip. The service rejects old
versions rather than guessing what a client meant.

The systems should converge below the application boundary and diverge above
it. RubyOS therefore does not transliterate PythonOS: its live workflow uses
anonymous Modules and class replacement, its scheduler exposes Fibers, its
driver model uses mixins and class DSLs, and its introspector reports actual
Ruby classes, methods, ivars, and object relationships.
