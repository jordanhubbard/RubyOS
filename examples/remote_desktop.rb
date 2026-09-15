# frozen_string_literal: true

require "rubyos"

host = ENV.fetch("RUBYOS_DISPLAY_HOST", "127.0.0.1")
port = Integer(ENV.fetch("RUBYOS_DISPLAY_PORT", "17010"))
transport = RubyOS::Bridge::Transport::TCP.new(host:, port:)
client = RubyOS::Bridge::Client.new(transport)
hello = client.hello
puts "connected to #{hello.fetch("service")} with SDL #{hello.fetch("sdl_ver")}"

desktop = nil
begin
  desktop = RubyOS::Bridge::RemoteDesktop.new(client, width: 720, height: 450,
                                             title: "RubyOS - Objects All The Way Down")
  root = RubyOS::GUI::Container.new(x: 0, y: 0, width: 720, height: 450,
                                  background: 0x130f1c)
  root.add(RubyOS::GUI::View.new(x: 24, y: 24, width: 672, height: 402,
                               background: 0x3b245c))
  root.add(RubyOS::GUI::View.new(x: 38, y: 76, width: 644, height: 330,
                               background: 0x21182f))
  root.add(RubyOS::GUI::Label.new("RubyOS", x: 48, y: 42, color: 0xffd866))
  root.add(RubyOS::GUI::Label.new("Objects all the way down", x: 48, y: 92,
                                color: 0xe8dff5))
  root.add(RubyOS::GUI::Label.new(RUBY_DESCRIPTION, x: 48, y: 122,
                                color: 0x9cdcfe))
  root.add(RubyOS::GUI::Label.new("Fiber scheduler  |  Ruby drivers  |  remote SDL",
                                x: 48, y: 152, color: 0xc3e88d))
  root.add(RubyOS::GUI::Label.new("Close this window or press Escape to return.",
                                x: 48, y: 370, color: 0xb8a8c9))
  root.draw(desktop.surface)
  desktop.present

  loop do
    events = desktop.events
    break if events.any? { |event| event["kind"] == 6 }
    break if events.any? { |event| event["kind"] == 1 && event["code"] == 27 }
    sleep 0.016
  end
ensure
  begin
    desktop&.close
    client&.call("shutdown")
  rescue StandardError
  end
  client&.close
end
