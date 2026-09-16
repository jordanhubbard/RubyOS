# frozen_string_literal: true
# Start services/remoteos-sdl/remoteos-sdl --listen-tcp 127.0.0.1:5001 first.
require "rubyos"
require "socket"
transport = RubyOS::Bridge::Transport::TCP.new(host: ENV.fetch("REMOTEOS_HOST", "127.0.0.1"),
                                              port: Integer(ENV.fetch("REMOTEOS_PORT", "5001")))
RubyOS::Media::Studio.open(RubyOS::Bridge::Client.new(transport), width: 640, height: 360) do |studio|
  scene = RubyOS::Media::Scene3D.new
  cube = scene.add(RubyOS::Media::Mesh.cube)
  sound = lambda do |time, count|
    RubyOS::Sound::PCM.new(count.times.map do |i|
      (Math.sin(2 * Math::PI * 220 * (time + i / 48000.0)) * 3000).round
    end)
  end
  movie = studio.record(seconds: 2, fps: 30, audio: sound) do |canvas, time|
    cube.rotation_x, cube.rotation_y = 0.3 + time, 0.5 + time
    canvas.render(scene)
    canvas.text("Made with RubyOS", x: 24, y: 24, color: 0xffffff)
  end
  puts studio.session.export("rubyos-studio.mkv", movie)
  studio.session.video(movie) do |video|
    video.play
    studio.run do |_, canvas|
      break if video.tick(canvas).fetch("eof")
    end
  end
end
