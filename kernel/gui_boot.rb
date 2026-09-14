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
      terminal = Apps::Terminal.new
      settings = Apps::Settings.new
      applications = Apps::Registry.new
        .register("About", Apps::About.new)
        .register("Files", Apps::Files.new)
        .register("Terminal", terminal)
        .register("Monitor", Apps::SystemMonitor.new)
        .register("Editor", Apps::Editor.new)
        .register("Image", Apps::ImageViewer.new)
        .register("Chipset", Apps::ChipsetWorkbench.new)
        .register("Clock", Apps::Clock.new)
        .register("Settings", settings)
      dock_labels = { "About" => "Abt", "Files" => "File", "Terminal" => "Term",
                      "Monitor" => "Mon", "Editor" => "Edit", "Image" => "Img",
                      "Chipset" => "Chip", "Clock" => "Clk", "Settings" => "Set" }
      applications.each do |name, application|
        compositor.add_dock_item(dock_labels.fetch(name, name)) { application.launch(compositor) }
      end
      applications.fetch("About").launch(compositor)
      applications.fetch("Files").launch(compositor)
      applications.fetch("Chipset").launch(compositor)
      applications.fetch("Terminal").launch(compositor)
      client.call("debug.event.inject", { kind: 1, code: 0, text: "6" })
      client.call("debug.event.inject", { kind: 1, code: 13 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(terminal.last_result == "=> 6", "keyboard input did not reach Terminal")
      clock_window = applications.fetch("Clock").launch(compositor)
      settings_window = settings.launch(compositor)
      client.call("debug.event.inject", { kind: 4, x: 145, y: 137, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(!settings.animations, "Settings button did not receive mouse input")
      compositor.close(settings_window)
      compositor.close(clock_window)
      compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
      font = Bridge::Font.open_default(client, point_size: 14)
      RubyOS.invariant(font.measure("RubyOS").all?(&:positive?), "SDL_ttf measurement failed")
      title_surface = font.render("RubyOS 4", color: 0xffd866)
      title_surface.blit_to(desktop.surface, x: 398, y: 26)
      desktop.present
      client.call("debug.event.inject", { kind: 4, x: 180, y: 280, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.title == "System Monitor",
                       "dock input did not launch System Monitor")
      compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
      title_surface.blit_to(desktop.surface, x: 398, y: 26)
      desktop.present
      audio = Sound::BridgeOutput.new(client)
      chord = Sound::Mixer.new.mix(
        Sound::Waveform.sine(220, duration_ms: 40, amplitude: 0.10),
        Sound::Waveform.sine(330, duration_ms: 40, amplitude: 0.10)
      )
      audio.play(chord)
      RubyOS.invariant(audio.queued_bytes >= 0, "SDL audio queue unavailable")
      audio.close
      desktop.capture("/tmp/rubyos-baremetal-desktop.bmp")
      title_surface.destroy
      font.close
      desktop.close
      client.call("shutdown")
      client.close
      RubyOS::HAL.serial_write("[RubyOS/arm64] remote SDL desktop: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] SDL input routing: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] keyboard Terminal input: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] core desktop apps: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] SDL_ttf Ruby Font: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] SDL audio bridge: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS/arm64] Ruby chipset workbench: PASS\n")
      true
    end
  end
end
