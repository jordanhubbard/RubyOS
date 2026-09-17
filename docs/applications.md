# RubyOS application toolkit

`RubyOS::App` is the public class library for portable RubyOS applications.
Application code owns a `Canvas`, receives input, advances state in `update`,
and sends optional PCM through `Audio`. It does not import or call SDL.

```ruby
class Hello < RubyOS::App::Base
  def initialize(audio: RubyOS::App::Audio.new)
    super(width: 320, height: 200, audio:)
    @x = 0
  end

  def update(seconds)
    @x = (@x + 80 * seconds).to_i % canvas.width
  end

  def input(event)
    audio.tone(660, duration_ms: 60) if event.fetch("kind", 0) == RubyOS::Input::KEY_DOWN
  end

  def draw(frame)
    frame.clear(0x07101e)
         .frame(2, 2, 316, 196, color: 0x51d6c5)
         .rect(@x, 80, 24, 24, color: 0xffd866)
         .text(16, 16, "HELLO RUBYOS", color: 0xffffff, scale: 2)
  end
end
```

The same class runs without the external service:

```ruby
backend = RubyOS::App::Backend::Memory.new
app = Hello.new
RubyOS::App::Runtime.new(app, backend:).run(frames: 60)
frame = backend.last_frame       # RubyOS::Media::Bitmap
```

or on RemoteOS-SDL:

```ruby
backend = RubyOS::App::Backend::RemoteSDL.new(
  client, width: 320, height: 200, title: "Hello"
)
audio = RubyOS::App::Audio.new(RubyOS::Sound::BridgeOutput.new(client))
app = Hello.new(audio:)
runtime = RubyOS::App::Runtime.new(app, backend:)
runtime.dispatch(backend.events.first)
runtime.frame
```

`Backend::Surface` is the adapter for a native framebuffer or any owned surface
that accepts 32-bit bitmap uploads. Inject the native HDA/VirtIO Sound output or
the SDL bridge output into `Audio`; application code is identical. The memory
backend is deterministic and is used for tests, captures, servers, and tools
that must run with no display service at all.

The toolkit deliberately exposes Ruby concepts rather than SDL handles:

- `Canvas`: pixels, rectangles, frames, lines, sprites, and portable block text
- `Base`: lifecycle (`start`, `input`, `update`, `draw`, `stop`)
- `Runtime`: fixed-step frames and event dispatch
- `Audio`: PCM and waveform tones over an injected output
- `Backend::Memory`, `Backend::Surface`, and `Backend::RemoteSDL`

Desktop applications that need menus, file dialogs, and standard controls can
subclass `RubyOS::Apps::Application`; their game/media cores can still use
`RubyOS::App::Canvas` and `Audio` so they remain independently runnable.
