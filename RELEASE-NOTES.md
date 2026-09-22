# RubyOS v0.4.0

## The desktop gets real type

Every string the GUI drew went through an embedded 8x8 bitmap font, one
`SDL_FillRect` per lit pixel, ASCII only. SDL_ttf had been available across the
bridge the whole time and nothing used it.

`RubyOS::GUI::Text` now routes every `draw_text` through TTF, caching rendered
runs host-side and falling back to the bitmap face on a host with no usable
font. Menlo at 14pt advances exactly 8 pixels — the same grid the bitmap font
used — so no layout had to move. The literal `8`s that *assumed* that grid are
gone regardless, replaced by the measured advance, because the next host's font
will not be Menlo. A proportional face is refused outright rather than laid out
on a column grid it does not honour.

Frames got cheaper in the process: one cached blit per string, against one fill
per lit pixel. Visual goldens pin themselves to the bitmap face so their tile
hashes stay reproducible on a host that ships DejaVu instead of Menlo.

## A dock with icons, and a desktop with a size

The dock painted text labels in boxes. It now paints centred square icons with
a hover label and a running-app pip. `RubyOS::GUI::Icons` declares each icon as
rectangles and lines on a 48x48 grid and renders it at whatever edge the dock
asks for, so a compact desktop gets a genuinely smaller icon rather than a
shrunken one. They are drawn rather than loaded because kernel sources are
embedded as a C string literal and have to stay 7-bit ASCII, which would make a
baked-in image cost several times its own size. The debug-grid wallpaper is now
a banded gradient.

The desktop was also fixed at 1024x768. It now treats that as a request:
`display.open` reports the framebuffer the host actually created and the guest
adopts it, which `RUBYOS_DESKTOP_SIZE=1920x1080 make run-gui` steers from the
host side. Window geometry follows, scaling against a 1024x768 reference and
capped at 2x, with anchored children riding the same relayout path a
resize-grip drag uses. At or below the reference it changes nothing.

The editor, launcher and inspector were still sized for a 480x300 screen and
clipped source mid-line on a full desktop. They now open at sizes that fit
their contents.

## Two allocator defects, one of them longstanding

`rubyos-arm64-gui-smoke` had been failing before this release. The reported
symptom was CRuby's `[FATAL] failed to allocate memory`, and the heap was not
the problem — it had over a hundred megabytes free at the moment it died.

`mmap` kept live mappings in a fixed table of 128 records. CRuby's GC takes a
mapping per heap page, so the table filled after a few megabytes of object heap
and `mmap` began returning `MAP_FAILED` with memory still plentiful. CRuby
reports that as exhaustion and aborts, which is why the failure looked like a
heap problem and why it was intermittent. The table now holds 16384 mappings.
Enlarging the guest heap does not help and enlarging it far enough to satisfy
the speculative 384 MiB allocation CRuby makes at startup actively hurts,
because the reservation then succeeds and consumes the heap.

Separately, the virtio-console bridge transport allocated a DMA buffer for
every message it wrote and never freed it, leaking a page per bridge message.
It now holds one bounce buffer and grows it on demand. The native-TCP transport
was never affected, which is why the desktop acceptance suite stayed green
throughout.

Bridge payloads also move by `memcpy` now rather than a Ruby call per byte.
arm64 had no bulk DMA primitive; it does now, and both architectures gained the
read direction.

## Everything from the unreleased 0.3.2

This release also carries the work prepared as 0.3.2, which was never tagged:
the full PythonOS behaviour surface expressed in Ruby, with complete system
applications, thirteen Ruby-focused demonstrations and five playable games, all
rendered and compared in frozen ARM64 and x86_64 guests.

That work brought responsive anchored layouts, resizable windows, app-aware
menus, persistent dock pins and shortcuts, shared file choosers, bounded
host/guest file transfer, transactional source editing and live Ruby object,
Fiber, driver and heap inspection. F5 opens the focused application's archived
Ruby source and replaces its class only after validation succeeds. The serial,
TCP and graphical consoles share one stateful shell with syntax-aware multiline
evaluation, completion, VFS-persistent history and streaming TCP file transfer.
`RubyOS::App` remains the supported backend-neutral application class library;
see `docs/applications.md`.

## Release validation

The release commit is accepted independently on Linux ARM64, Linux x86_64 and
Apple Silicon macOS. ARM64 and x86_64 frozen guests boot the expanded console,
network stack and native-TCP desktop, while architecture-specific visual
goldens cover every application and the interaction captures. Both golden sets
were refreshed for the new dock and wallpaper and then re-verified in a
separate run, since a refresh passes by construction.

Pins RemoteOS-SDL 0.3.0.

[RubyOS v0.4.0](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.4.0).
