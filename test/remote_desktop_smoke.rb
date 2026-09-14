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
  "SDL_VIDEODRIVER" => "dummy"
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
  desktop.present
  raise "event response is not an array" unless desktop.events.is_a?(Array)
  injected = client.call("debug.event.inject", { kind: 4, x: 20, y: 30, button: 1 })
  raise "event injection failed" unless injected.fetch("queued")
  event = desktop.events.fetch(0)
  raise "wrong injected event" unless event["kind"] == 4 && event["x"] == 20 && event["y"] == 30
  desktop.capture(capture_path)
  raise "desktop capture is empty" unless File.size?(capture_path)
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
