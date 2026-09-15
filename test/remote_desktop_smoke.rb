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
                           File.join(root, "services", "remoteos-sdl", "remoteos-sdl"),
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
  raise "wrong remote service" unless hello.fetch("service") == "remoteos-sdl"
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
  jpeg = ["ffd8ffe000104a46494600010200000100010000fffe000f4c61766336312e332e31303000ffdb0043000804040404040505050505050606060606060606060606060607070708080807070706060707080808080909090808080809090a0a0a0c0c0b0b0e0e0e111114ffc400680001010000000000000000000000000000050601010100000000000000000000000000000506100001040101090100000000000000000003040602010500a58555171314b408d436110002020202030101000000000000000003020104061211051300221421ffc00011080008000803012200021100031100ffda000c03010002110311003f003530f38ce6385623b922c88b18d29368973129b064a69151b23d0a2c8c20d2830d3f75125440a2231c6553842aa89e727b47c7367b4be2d543cff14d5dc3e129d03a530ec729659d0d7ef2d9ad5535ce61abd22286987f2c4535f00586494f22d7831bee7739084fe6dc7b4380d2abd8a64697022b6d4322bdd608c718cc670d40551ab95c8ad2c524ec4332eaac5766d639f7ffd9"].pack("H*")
  decoded_jpeg = RubyOS::Bridge::Surface.load_image(client, jpeg)
  raise "JPEG dimensions changed" unless [decoded_jpeg.width, decoded_jpeg.height] == [8, 8]
  decoded_jpeg.blit_to(desktop.surface, x: 448, y: 20)
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
  performance = client.performance_snapshot
  guest_present = performance.fetch(:guest_round_trip).fetch("frame.commit")
  host_present = performance.fetch(:host_service).fetch("ops").fetch("frame.commit")
  raise "guest bridge timing missing" unless guest_present.fetch(:count).positive?
  raise "host bridge timing missing" unless host_present.fetch("count").positive?
  image.destroy
  decoded.destroy
  decoded_jpeg.destroy
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
