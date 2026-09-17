# RubyOS v0.3.1

## A fresh checkout now knows how to become a development machine

`make install` is the supported bootstrap entry point on ARM64 and x86_64
macOS, Debian/Ubuntu Linux and Windows WSL2. It installs the SDL, FFmpeg, QEMU,
Ruby build and filesystem dependencies through Homebrew or apt, initializes
the shared RemoteOS-SDL submodule, starts Docker where the host permits it and
prepares the native-host cross-toolchain image.

The regular build also initializes the display-service submodule if an
existing clone omitted it. Linux container commands can fall back through
`sudo` immediately after Docker installation, rather than requiring a logout
before the first RubyOS build. WSL2 keeps the same build surface on both host
architectures; interactive windows require WSLg, while headless tests do not.

## ARM64 RAM is RAM now

The ARM64 bootstrap establishes an EL1 identity map before CRuby starts. QEMU
MMIO below 1 GiB retains device-memory semantics, while RAM beginning at
`0x40000000` is normal write-back memory. This fixes the alignment exceptions
previously raised by valid CRuby scalar and SIMD accesses during ractor and
Prism initialization.

The same translation setup runs on application processors. Console boot, the
persistent desktop, native-TCP GUI/media, and four-core worker paths now pass
on ARM64. The x86_64 console and desktop paths remain covered independently.

## The interactive desktop fails clearly instead of hanging

Pointer clicks on text fields and other non-button views no longer arrive as
synthetic button events. This fixes the guest exception previously triggered
by clicking the Terminal or Editor after the desktop reported itself ready.

The public GUI supervisor now watches the guest serial log for fatal markers.
If the guest raises unexpectedly, it terminates the checkout's QEMU and SDL
children and returns a failing status with the diagnostic log path instead of
leaving an apparently live window forever.

## Installation is part of the release gate

Installer routing is tested for macOS, Debian/Ubuntu Linux and WSL2 on both
ARM64 and x86_64. Release CI now invokes `make install` instead of maintaining
a second handwritten dependency list, so the documented first-run path and
the path used to create release artifacts cannot silently diverge.

[RubyOS v0.3.1](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.3.1).
