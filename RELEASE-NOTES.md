# RubyOS v0.3.0

## Ruby gets a studio, not a commemorative chipset

RubyOS now has block-scoped SDL resources, 2D scenes, perspective 3D meshes,
seekable property animation, PCM composition, video playback and audiovisual
recording. Ruby objects describe what happens. RemoteOS-SDL handles host
rendering and codecs. Nobody has to pretend a copper list is a personality.

The old chipset hierarchy is removed. Invaders and Snake retain their gameplay
while rendering through ordinary bitmap objects. The desktop's Media Workbench
replaces its hardware-homage laboratory.

## Make something, then play it back

The source-built CRuby 4.0.6 runtime remains the language engine. Run
`examples/studio.rb` for an animated cube with text, or `examples/movie.rb`
to record a two-second audiovisual scene, export it as Matroska and play it.
[The multimedia guide](docs/multimedia.md) supplies complete launch commands.

`Studio#record` advances its timeline in fixed steps. A Ruby audio callback
supplies PCM per frame; the service encodes MPEG-4 video and muxes both tracks.
`Video#play`, `pause`, `seek` and `tick` expose host audio-clocked playback.
Resources close with their blocks; drawing batches obey negotiated limits and
report errors. Small pleasures, such as not leaking a font every frame.

## Platforms and honest limits

Hosted integration and ARM64/x86_64 bare-metal native-TCP tests cover 3D,
export and playback. Linux ARM64, Linux x86_64 and macOS ARM64 release gates
use the pinned shared service. Linux bundles retain both guest architectures.
Windows uses WSL2, not a native Windows kernel build.

The framework is not a finished video editor. Clip bytes cap at 16 MiB,
audio predecode/export at 60 seconds, and export uses even dimensions up to
2048 with fixed integer frame rates. OpenGL has readback and a software fallback;
textures, lighting and streaming remain outside this release. See the guide
for ownership, clock precision, codec and transport boundaries.

Executive summary: a Ruby-focused multimedia foundation, two real guest CPU
architectures, and substantially fewer reasons to role-play a 1980s chipset.
[RubyOS v0.3.0](https://github.com/jordanhubbard/RubyOS/releases/tag/v0.3.0).
