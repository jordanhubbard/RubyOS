# frozen_string_literal: true
require "rubyos"
def assert(value) = (raise "assertion failed" unless value)
media = RubyOS::Media
assert(media::Color.hex("#51d6c5") == media::Color.rgb(81, 214, 197))
bitmap = media::Bitmap.new(2, 2).rect(0, 0, 1, 2, color: 0x123456)
assert(bitmap.bytes.unpack("L<*") == [0x123456, 0, 0x123456, 0])
clipped = media::Bitmap.new(8, 4)
clipped.line(-1_000_000, 2, 1_000_000, 2, color: 0xabcdef)
assert(8.times.all? { |x| clipped.get(x, 2) == 0xabcdef })
revision = clipped.revision
clipped.line(-1_000_000, -1_000_000, -2, -2, color: 0xffffff)
assert(clipped.revision == revision)
stamp = media::Bitmap.new(2, 2)
stamp.put(0, 0, 0xff0000).put(1, 1, 0x00ff00)
canvas = media::Bitmap.new(4, 4, background: 0x010203)
canvas.blit(stamp, 1, 1, key: 0)
assert(canvas.get(1, 1) == 0xff0000 && canvas.get(2, 2) == 0x00ff00 &&
       canvas.get(2, 1) == 0x010203)
square = RubyOS::Sound::Waveform.square(100, duration_ms: 20, rate: 1_000)
triangle = RubyOS::Sound::Waveform.triangle(100, duration_ms: 20, rate: 1_000)
assert(square.samples.uniq.length == 2 && triangle.samples.uniq.length > 2)
shape = media::Shape.new(x: 0, y: 0)
timeline = media::Timeline.new
timeline.animate(shape, :x, from: 0, to: 10, duration: 1, easing: :linear)
timeline.animate(shape, :x, from: 10, to: 20, duration: 1, delay: 1, easing: :linear)
timeline.seek(0.5); assert(shape.x == 5)
timeline.seek(1.5); assert(shape.x == 15)
timeline.seek(0); assert(shape.x == 0)
source = media::Bitmap.new(4, 2, background: 0x111111)
destination = media::Bitmap.new(4, 2, background: 0xeeeeee)
wipe = media::WipeTransition.new(source:, destination:, progress: 0.5)
assert(wipe.output.raster == [0xeeeeee, 0xeeeeee, 0x111111, 0x111111] * 2)
wipe.direction = :bottom_to_top
assert(wipe.output.raster == [0x111111] * 4 + [0xeeeeee] * 4)
wipe.progress = 1
assert(wipe.complete? && wipe.output.raster.all? { |pixel| pixel == 0xeeeeee })
begin
  media::WipeTransition.new(source:, destination: media::Bitmap.new(3, 2))
  raise "mismatched wipe dimensions accepted"
rescue ArgumentError
end
scene = media::Scene3D.new
scene.add(media::Mesh.cube)
vertices = scene.vertices(aspect: 1.5)
assert(vertices.size == 36 && vertices.all? { |v| v.size == 7 && v.all?(&:finite?) && v[3] > 0 })
puts "RubyOS media model: PASS"
