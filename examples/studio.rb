# frozen_string_literal: true
# Start RemoteOS-SDL with --listen-tcp 127.0.0.1:5001 first.
require "rubyos"
require "socket"

transport = RubyOS::Bridge::Transport::TCP.new(host: ENV.fetch("REMOTEOS_HOST", "127.0.0.1"),
                                              port: Integer(ENV.fetch("REMOTEOS_PORT", "5001")))
client = RubyOS::Bridge::Client.new(transport)
RubyOS::Media::Studio.open(client, width: 960, height: 600, title: "RubyOS · Studio") do |studio|
  scene = RubyOS::Media::Scene3D.new(background: 0x101521)
  cube = scene.add(RubyOS::Media::Mesh.cube)
  studio.session.font(size: 28) do |font|
    title = font.render("Make something beautiful.", color: 0xe5eaf5)
    frames = ENV["RUBYOS_STUDIO_FRAMES"] && Integer(ENV.fetch("RUBYOS_STUDIO_FRAMES"))
    studio.run(frames:) do |_, canvas|
      cube.rotation_y = 0.5 + studio.timeline.time * 0.6
      cube.rotation_x = 0.3 + studio.timeline.time * 0.25
      canvas.render(scene)
      canvas.rect(0, 0, 960, 90, color: 0x182132)
      canvas.blit(title, x: 32, y: 24)
      canvas.text("RUBYOS / LIVE SCENES / SHARED REMOTEOS", x: 32, y: 558, color: 0x51d6c5)
    end
    studio.session.capture(ENV.fetch("RUBYOS_STUDIO_CAPTURE")) if ENV["RUBYOS_STUDIO_CAPTURE"]
  end
end
