# frozen_string_literal: true

require "socket"
require "timeout"
require "rubyos"

root = File.expand_path("..", __dir__)
listener = TCPServer.new("127.0.0.1", 0)
port = listener.local_address.ip_port
listener.close
log_path = File.join(root, "build", "rubyos-bridge-smoke.log")
capture_path = File.join(root, "build", "rubyos-remote-desktop.bmp")

environment = {
  "RUBYOS_DESKTOP_MODE" => "headless",
  "SDL_VIDEODRIVER" => "dummy",
  "SDL_AUDIODRIVER" => "dummy"
}
bridge_pid = Process.spawn(environment,
                           File.join(root, "bridge", "rubyos_bridge"),
                           "--listen-tcp", "127.0.0.1:#{port}",
                           out: log_path, err: [:child, :out])
client = nil
bridge_status = nil

begin
  transport = nil
  Timeout.timeout(5) do
    loop do
      begin
        transport = RubyOS::Bridge::Transport::TCP.new(host: "127.0.0.1", port:)
        break
      rescue Errno::ECONNREFUSED
        sleep 0.02
      end
    end
  end

  client = RubyOS::Bridge::Client.new(transport)
  hello = client.hello
  raise "wrong bridge agent" unless hello.fetch("agent") == "rubyos_bridge"
  raise "audio feature missing" unless client.features.include?("audio.pcm")

  desktop = RubyOS::Bridge::RemoteDesktop.new(client, width: 480, height: 300,
                                               title: "RubyOS Remote Desktop")
  root_view = RubyOS::GUI::Container.new(x: 0, y: 0, width: 480, height: 300,
                                         background: 0x171321)
  root_view.add(RubyOS::GUI::View.new(x: 24, y: 24, width: 432, height: 252,
                                      background: 0x3b245c))
  root_view.add(RubyOS::GUI::View.new(x: 36, y: 58, width: 408, height: 196,
                                      background: 0x21182f))
  root_view.add(RubyOS::GUI::Label.new("Ruby owns this desktop", x: 52, y: 78,
                                       color: 0xffd866))
  root_view.add(RubyOS::GUI::Label.new("CRuby 4 + Prism + SDL", x: 52, y: 104,
                                       color: 0x9cdcfe))
  root_view.draw(desktop.surface)
  pixels = [0x20, 0x66, 0xff, 0, 0x66, 0xcc, 0x44, 0,
            0xff, 0x66, 0x99, 0, 0xcc, 0xcc, 0x55, 0].pack("C*")
  image = RubyOS::Bridge::Surface.create(client, width: 2, height: 2)
  image.upload(pixels).blit_to(desktop.surface, x: 440, y: 20)
  png = ["89504e470d0a1a0a0000000d494844520000000200000002010300000048789f67" \
         "00000006504c5445ff3366ffffffb9d15e980000000c4944415408d763606060" \
         "0000000400012734270a0000000049454e44ae426082"].pack("H*")
  decoded = RubyOS::Bridge::Surface.load_image(client, png)
  decoded.blit_to(desktop.surface, x: 444, y: 20)
  font = RubyOS::Bridge::Font.open_default(client, point_size: 14)
  measured = font.measure("Ruby")
  raise "invalid SDL_ttf measurement" unless measured.all?(&:positive?)
  rendered_text = font.render("Ruby", color: 0xffd866)
  rendered_text.blit_to(desktop.surface, x: 390, y: 270)
  audio = RubyOS::Sound::BridgeOutput.new(client)
  audio.play(RubyOS::Sound::Waveform.sine(440, duration_ms: 10))
  raise "audio queue status invalid" unless audio.queued_bytes >= 0
  audio.close
  desktop.present
  raise "event response is not an array" unless desktop.events.is_a?(Array)
  injected = client.call("debug.event.inject", { kind: 4, x: 20, y: 30, button: 1 })
  raise "event injection failed" unless injected.fetch("queued")
  event = desktop.events.fetch(0)
  raise "wrong injected event" unless event["kind"] == 4 && event["x"] == 20 && event["y"] == 30
  desktop.capture(capture_path)
  raise "desktop capture is empty" unless File.size?(capture_path)
  image.destroy
  decoded.destroy
  rendered_text.destroy
  font.close
  desktop.close
  client.call("shutdown")
  client.close
  Process.wait(bridge_pid)
  bridge_status = $?
  raise "bridge exited unsuccessfully" unless bridge_status.success?
  puts "RubyOS SDL remote desktop smoke: PASS"
ensure
  unless bridge_status
    begin
      client&.call("shutdown")
      client&.close
    rescue StandardError
    end
    begin
      Timeout.timeout(2) { Process.wait(bridge_pid) }
    rescue Timeout::Error
      Process.kill("KILL", bridge_pid)
      Process.wait(bridge_pid)
    rescue Errno::ECHILD
    end
  end
end
