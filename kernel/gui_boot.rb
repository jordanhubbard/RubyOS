# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_remote_desktop
      transport = Bridge::Transport::VirtioConsole.find
      client = Bridge::Client.new(transport)
      hello = client.hello
      RubyOS.invariant(hello.fetch("agent") == "rubyos_bridge",
                       "unexpected remote desktop agent")

      desktop = Bridge::RemoteDesktop.new(client, width: 480, height: 300,
                                           title: "RubyOS Bare-Metal Desktop")
      compositor = GUI::Compositor.new(width: 480, height: 300, title: "RubyOS")
      applications = Apps::Registry.new
        .register("About", Apps::About.new)
        .register("Files", Apps::Files.new)
        .register("Terminal", Apps::Terminal.new)
        .register("Monitor", Apps::SystemMonitor.new)
      applications.each do |name, application|
        compositor.add_dock_item(name) { application.launch(compositor) }
      end
      applications.fetch("About").launch(compositor)
      applications.fetch("Files").launch(compositor)
      applications.fetch("Terminal").launch(compositor)
      compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
      desktop.present
      client.call("debug.event.inject", { kind: 4, x: 260, y: 280, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.title == "System Monitor",
                       "dock input did not launch System Monitor")
      compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
      desktop.present
      desktop.capture("/tmp/rubyos-baremetal-desktop.bmp")
      desktop.close
      client.call("shutdown")
      client.close
      RubyOS::HAL.serial_write("[RubyOS/arm64] remote SDL desktop: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] SDL input routing: PASS\n")
      true
    end
  end
end
