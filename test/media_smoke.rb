# frozen_string_literal: true
require "rubyos"
require "socket"
require "tmpdir"
require "timeout"

Dir.mktmpdir("rubyos-media-") do |dir|
  clip = File.join(dir, "clip.avi")
  raise "ffmpeg failed" unless system("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=red:s=64x48:r=5", "-frames:v", "5", "-c:v", "mpeg4", "-bf", "2", clip)
  listener = TCPServer.new("127.0.0.1", 0)
  port = listener.local_address.ip_port
  listener.close
  binary = ENV.fetch("REMOTEOS_SDL_BIN", File.expand_path("../services/remoteos-sdl/remoteos-sdl", __dir__))
  pid = Process.spawn({ "SDL_VIDEODRIVER" => "dummy", "SDL_AUDIODRIVER" => "dummy", "REMOTEOS_SDL_MODE" => "headless" }, binary, "--listen-tcp", "127.0.0.1:#{port}")
  begin
    transport = Timeout.timeout(10) do
      loop do
        begin
          break RubyOS::Bridge::Transport::TCP.new(host: "127.0.0.1", port:)
        rescue Errno::ECONNREFUSED
          sleep 0.02
        end
      end
    end
    client = RubyOS::Bridge::Client.new(transport)
    RubyOS::SDL.open(client) do |session|
      studio = RubyOS::Media::Studio.new(session, width: 320, height: 240)
      scene = RubyOS::Media::Scene3D.new
      cube = scene.add(RubyOS::Media::Mesh.cube)
      studio.timeline.animate(cube, :rotation_y, to: 2, duration: 1)
      studio.run(frames: 3) do |_, canvas|
        canvas.render(scene)
        canvas.text("RubyOS Studio", x: 10, y: 10)
      end
      600.times { |i| studio.canvas.rect(i % 320, i % 240, 1, 1, color: 0xffffff) }
      studio.display.present_async
      session.font(size: 14) do |font|
        text = font.render("Beautiful Ruby")
        studio.canvas.blit(text, x: 20, y: 200)
        text.close
        raise "resource retained" if session.instance_variable_get(:@resources).include?(text)
      end
      session.audio do |audio|
        RubyOS::Media::AudioTrack.new(audio).tone(440, duration: 0.01).play
        raise "bad audio status" unless audio.queued_bytes >= 0
      end
      session.video(File.binread(clip)) do |video|
        times = []
        while (time = video.frame(studio.canvas))
          times << time
        end
        raise "video frames" unless times.length == 5 && times == times.sort
        video.seek(0)
        raise "seek failed" unless video.frame(studio.canvas)
      end
      encoded = studio.record(seconds: 0.2, fps: 10,
        audio: ->(_time, count) { RubyOS::Sound::PCM.new(Array.new(count, 100)) }) do |canvas, time|
        cube.rotation_y = time
        canvas.render(scene)
      end
      raise "empty recording" unless encoded.bytesize > 1000
      session.video(encoded) do |video|
        video.play
        result = video.tick(studio.canvas)
        raise "playback stopped" unless result.fetch("playing")
        video.pause.seek(0)
        raise "pause failed" if video.tick(studio.canvas).fetch("playing")
      end
      studio.display.present
      session.capture(File.join(dir, "studio.bmp"))
      raise "capture missing" unless File.size?(File.join(dir, "studio.bmp"))
      raise "telemetry missing" unless session.performance.fetch(:host_service).fetch("ops").key?("scene3d.render")
      canvas = session.canvas(width: 2, height: 2)
      canvas.close
      begin
        canvas.clear
        raise "closed canvas accepted"
      rescue RubyOS::SDL::ClosedResource
      end
      studio.display.close
      session.call("shutdown")
    end
    Timeout.timeout(5) { Process.wait(pid) }
    pid = nil
    puts "RubyOS SDL multimedia integration: PASS"
  ensure
    if pid
      Process.kill("KILL", pid) rescue Errno::ESRCH
      Process.wait(pid) rescue Errno::ECHILD
    end
  end
end
