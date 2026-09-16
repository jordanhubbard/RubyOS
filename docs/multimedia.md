# RubyOS multimedia: first iteration

Ruby owns scenes, objects, animation and composition. RemoteOS-SDL owns host
rendering, decoding and devices. There is no emulated Amiga chipset: the games
use ordinary `Media::Bitmap` images, and the desktop has a Media Workbench.
This is a creation-framework foundation, not a finished audiovisual editor.

## Try it

RubyOS pins RemoteOS-SDL 0.2.0. Initialize submodules and install the README's
SDL/FFmpeg/OpenGL dependencies before building.

```sh
make test-host
make test-media
services/remoteos-sdl/remoteos-sdl --listen-tcp 127.0.0.1:5001
# In another terminal, using our privately source-built Ruby:
build/host-ruby/bin/ruby -I kernel examples/studio.rb
# Or record, export and play a two-second audiovisual movie:
build/host-ruby/bin/ruby -I kernel examples/movie.rb
```

The example animates a colored cube with a typographic 2D overlay. Closing its
window exits and releases resources. The service listener remains available.
Loopback is the default example boundary; do not expose this development
endpoint to untrusted networks.

## Ruby API

`RubyOS::SDL.open(client) { |session| ... }` owns resources and closes them in
reverse creation order. `canvas`, `font`, `audio`, `video`, `encoder`, `image` and `display`
support block-scoped ownership. Closed or cross-session resources are rejected.
Drawing batches automatically at the negotiated limit; calls and presentation
flush ordered work, and batch failures raise exceptions.

```ruby
session.canvas(width: 640, height: 360) do |canvas|
  canvas.clear(0x101521).rect(20, 20, 80, 40, color: 0x51d6c5)
  scene = RubyOS::Media::Scene3D.new
  scene.add(RubyOS::Media::Mesh.cube)
  canvas.render(scene) # host depth buffer and clipping
end

session.audio do |audio|
  RubyOS::Media::AudioTrack.new(audio).tone(440, duration: 0.25).play
end

session.video(encoded_bytes) do |video|
  timestamp = video.frame(destination_canvas) # nil at end of stream
  video.seek(0)
end

# Or let the host schedule frames against consumed audio samples:
session.video(encoded_bytes) do |video|
  video.play
  studio.run do |_, canvas|
    break if video.tick(canvas).fetch("eof")
  end
end
```

`Media::Scene` composes 2D shapes/text; `Scene3D` composes colored triangle
meshes with a perspective camera. `Timeline` provides seekable linear/smooth
property animation. `Studio` combines display, timeline and a paced frame loop.
Image decoding, TrueType fonts, input/injection, file-token import, file export,
capture and guest/host performance counters have named session methods.
`session.sdl(name, *args)` exposes the service's registered SDL functions;
`session.call` is the explicit escape hatch for protocol operations.

## Limits and next work

3D selects OpenGL when available, with a software depth-buffer fallback.
`REMOTEOS_3D_BACKEND=opengl` requires OpenGL; `software` forces software.
This iteration sends transformed vertices per frame and reads pixels back;
it is not a retained GPU scene or a performance claim. No textures or lighting yet.

Video decodes an in-memory clip through FFmpeg: at most 16 MiB encoded,
four open clips, 4096-pixel source dimensions; Ruby canvases cap at 2048.
Frames return presentation timestamps. Seeking goes to an earlier keyframe;
the caller advances and schedules frames. Missing timestamps use the guessed
frame rate (30 fps fallback). Do not mix manual `frame` decoding with timed
playback on one handle without seeking first.

Timed playback predecodes at most 60 seconds of audio into 48 kHz stereo,
preserving timestamp gaps. Video follows SDL's consumed-sample counter, then
a monotonic clock after the audio ends; video-only clips use the monotonic
clock. Call `tick` regularly and present the canvas. `pause` freezes the clock;
`seek` replaces queued audio and clears pending video. Output-device buffering
adds latency: this is queue-clock synchronization, not sample-exact speaker
measurement. Audio device availability may limit simultaneous playback; close
separate PCM output before playing a movie on single-device backends.

`Studio#record(seconds:, fps:, audio: callback)` renders deterministic timeline
steps and returns Matroska bytes. Each block receives canvas and timeline time.
The optional callback receives time and sample count, returning a 48 kHz PCM
object or stereo S16LE bytes. The lower-level `session.encoder` accepts individual
surfaces with PCM trailers. Export uses MPEG-4 video plus PCM, even dimensions
2..2048, fps 1..60 dividing 48000, at most 60 seconds and 16 MiB output. Two
encoders can be open. `session.export("movie.mkv", bytes)` uses the host's
file-export policy; the guest does not choose arbitrary host paths.

Streaming, retained GPU geometry, textures/lighting and a nonlinear editor
remain outside this release. Codec APIs use FFmpeg's public decode, resample
and mux interfaces; see the [upstream resampling reference](https://ffmpeg.org/doxygen/trunk/group__lswr.html).

Run strict native guest checks against the new service with:

```sh
RUBYOS_REQUIRE_MEDIA=1 make rubyos-arm64-tcp-gui-smoke rubyos-x86_64-tcp-gui-smoke
```

CI requires these capabilities. For coordinated local development only, use
`REMOTEOS_SDL_DIR=../RemoteOS-SDL` to build and test the canonical sibling tree.
