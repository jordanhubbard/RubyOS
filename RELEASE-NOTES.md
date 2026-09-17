# RubyOS v0.3.2

## PythonOS breadth and depth, expressed as Ruby

RubyOS now covers the measured PythonOS behavior surface while keeping Ruby's
object model and idioms at the center. The catalog contains complete system
applications, thirteen Ruby-focused demonstrations and five playable games.
Every catalog entry is rendered and compared in frozen ARM64 and x86_64 guests;
the same acceptance suites exercise real guest file dragging and animated media
transitions.

The desktop has moved well beyond static showcase windows. It includes
responsive anchored layouts, resizable windows, app-aware menus, persistent
dock pins and shortcuts, shared file choosers, bounded host/guest file transfer,
transactional source editing, scrollable runtime tools, and live Ruby object,
Fiber, driver and heap inspection. F5 opens the focused application's archived
Ruby source and safely replaces its class only after validation succeeds.

## A genuinely interactive Ruby environment

The serial, TCP and graphical consoles now share one stateful shell. It provides
syntax-aware multiline Ruby evaluation, command/path/method completion,
VFS-persistent Terminal history, a current directory, file copy/move, Ruby
source execution, task lifecycle controls, system and network inspection,
desktop/editor launch, and streaming TCP file transfer.

Structured concurrency remains idiomatic Ruby: cooperative Fibers gain
join/gather, monotonic timeouts, bounded Enumerable channels, events,
block-scoped semaphores and task groups. Eighteen readable lessons across
eleven tracks demonstrate these APIs alongside modern language, storage,
networking, graphics, audio, web and internals examples.

## Ruby-native graphics, media and applications

The interactive desktop now matches PythonOS at 1024x768. Games use a larger
640x400 presentation with shaded sprite cells instead of nearest-neighbor
blocks, and all five titles route audible Ruby-generated sound-effect cues
through the desktop PCM device.

This release also establishes `RubyOS::App`, the supported application class
library. A Ruby application targets Canvas, lifecycle, input and Audio objects,
then selects an in-memory/native-surface or RemoteOS-SDL backend. SDL is an
optional device service, not an application programming model; the same app
logic and renderer run without it. See `docs/applications.md`.

The Image Viewer handles BMP, PNG, JPEG and P3/P6 portable pixmaps. The Media
Workbench is a two-program studio with direct cuts, four-direction seekable
wipes, a timeline, live meters, keyboard/menu control and Ruby-generated PCM
cues. The graphical catalog adds Enumerable, Fiber and pattern-matching labs;
Life, Mandelbrot, Spirograph, Paint, immutable-Data animation, Plasma, event,
sprite and tone demonstrations; and Invaders, Snake, Maze, Raiders and Defender.

Remote bitmap surfaces now have explicit bounded lifetimes, preventing cached
capture resources from accumulating across long ARM64 desktop acceptance runs.
The TCP stack also exposes active stream connections and treats FIN as EOF,
which supports the shell's bounded file-transfer workflow.

## Release validation

The release commit is accepted independently on Linux ARM64, Linux x86_64 and
Apple Silicon macOS. ARM64 and x86_64 frozen guests boot the expanded console,
network stack and native-TCP desktop, while architecture-specific visual
goldens cover every application and the interaction captures described above.

[RubyOS v0.3.2](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.3.2).
