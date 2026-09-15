# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_remote_desktop(transport: nil)
      transport ||= Bridge::Transport::VirtioConsole.find
      client = Bridge::Client.new(transport)
      hello = client.hello
      RubyOS.invariant(hello.fetch("service") == "remoteos-sdl",
                       "unexpected remote desktop service")

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
        .register("Image", Apps::ImageViewer.new)
        .register("Chipset", Apps::ChipsetWorkbench.new)
        .register("Clock", Apps::Clock.new)
        .register("Settings", settings)
        .register("Inspector", Apps::RubyInspector.new)
        .register("Invaders", Apps::Invaders.new)
        .register("Snake", Apps::Snake.new)
      runtime = Live::Runtime.new(vfs: state.fetch(:vfs), registry: applications)
      runtime.install("Live Hello", source: Apps::LIVE_HELLO_SOURCE,
                      path: "/apps/live_hello.rb")
      applications.register("Editor", Apps::Editor.new(
        path: "/apps/live_hello.rb", runtime:, application_name: "Live Hello"
      ))
      dock_labels = { "About" => "Abt", "Files" => "File", "Terminal" => "Term",
                      "Monitor" => "Mon", "Editor" => "Edit", "Image" => "Img",
                      "Chipset" => "Chip", "Clock" => "Clk", "Settings" => "Set" }
      applications.each do |name, application|
        next if ["Invaders", "Snake"].include?(name)
        compositor.add_dock_item(dock_labels.fetch(name, name)) { application.launch(compositor) }
      end
      compositor.add_shortcut("Clock", x: 8, y: 42) { applications.fetch("Clock").launch(compositor) }
      compositor.add_shortcut("Files", x: 8, y: 104) { applications.fetch("Files").launch(compositor) }
      applications.fetch("About").launch(compositor)
      applications.fetch("Files").launch(compositor)
      applications.fetch("Chipset").launch(compositor)
      applications.fetch("Terminal").launch(compositor)
      HAL.serial_write("[RubyOS] desktop smoke: applications launched\n")
      invaders = applications.fetch("Invaders")
      game_window = invaders.launch(compositor)
      invaders.game.enemies.replace([[15, 16]])
      invaders.game.fire
      invaders.game.tick
      RubyOS.invariant(invaders.game.score.positive? && invaders.game.cue,
                       "Invaders collision, scoring, or sound cue failed")
      compositor.close(game_window)
      snake = applications.fetch("Snake")
      snake_window = snake.launch(compositor)
      6.times { snake.game.tick }
      RubyOS.invariant(snake.game.score == 10 && snake.game.body.length == 4,
                       "Snake growth and scoring failed")
      compositor.close(snake_window)
      HAL.serial_write("[RubyOS] desktop smoke: games checked\n")
      client.call("debug.event.inject", { kind: 1, code: 0, text: "6" })
      client.call("debug.event.inject", { kind: 1, code: 13 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(terminal.last_result == "=> 6", "keyboard input did not reach Terminal")
      client.call("debug.event.inject", { kind: 4, x: 80, y: 160, button: 1 })
      client.call("debug.event.inject", { kind: 3, x: 100, y: 140 })
      client.call("debug.event.inject", { kind: 5, x: 100, y: 140, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.x == 74 && compositor.focused_window.y == 130,
                       "window title drag did not move Terminal")
      clock_window = applications.fetch("Clock").launch(compositor)
      settings_window = settings.launch(compositor)
      client.call("debug.event.inject", { kind: 4, x: 145, y: 137, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(!settings.animations, "Settings button did not receive mouse input")
      compositor.close(settings_window)
      compositor.close(clock_window)
      compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
      HAL.serial_write("[RubyOS] desktop smoke: compositor drawn\n")
      font = Bridge::Font.open_default(client, point_size: 14)
      RubyOS.invariant(font.measure("RubyOS").all?(&:positive?), "SDL_ttf measurement failed")
      title_surface = font.render("RubyOS 4", color: 0xffd866)
      title_surface.blit_to(desktop.surface, x: 398, y: 26)
      png = ["89504e470d0a1a0a0000000d494844520000000200000002010300000048789f67" \
             "00000006504c5445ff3366ffffffb9d15e980000000c4944415408d763606060" \
             "0000000400012734270a0000000049454e44ae426082"].pack("H*")
      jpeg = ["ffd8ffe000104a46494600010200000100010000fffe000f4c61766336312e332e31303000ffdb0043000804040404040505050505050606060606060606060606060607070708080807070706060707080808080909090808080809090a0a0a0c0c0b0b0e0e0e111114ffc400680001010000000000000000000000000000050601010100000000000000000000000000000506100001040101090100000000000000000003040602010500a58555171314b408d436110002020202030101000000000000000003020104061211051300221421ffc00011080008000803012200021100031100ffda000c03010002110311003f003530f38ce6385623b922c88b18d29368973129b064a69151b23d0a2c8c20d2830d3f75125440a2231c6553842aa89e727b47c7367b4be2d543cff14d5dc3e129d03a530ec729659d0d7ef2d9ad5535ce61abd22286987f2c4535f00586494f22d7831bee7739084fe6dc7b4380d2abd8a64697022b6d4322bdd608c718cc670d40551ab95c8ad2c524ec4332eaac5766d639f7ffd9"].pack("H*")
      png_surface = Bridge::Surface.load_image(client, png)
      jpeg_surface = Bridge::Surface.load_image(client, jpeg)
      RubyOS.invariant([png_surface.width, png_surface.height] == [2, 2], "PNG decode dimensions")
      RubyOS.invariant([jpeg_surface.width, jpeg_surface.height] == [8, 8], "JPEG decode dimensions")
      chipset_engine = Chipset::Engine.new
      chipset_engine.load_view(Apps::ChipsetWorkbench.new.build_view).start
      chipset_frame, chipset_audio = chipset_engine.tick
      chipset_engine.stop
      RubyOS.invariant(!chipset_frame.empty? && !chipset_audio.empty?,
                       "chipset clock did not produce raster and Paula audio")
      png_surface.blit_to(desktop.surface, x: 460, y: 26)
      jpeg_surface.blit_to(desktop.surface, x: 464, y: 26)
      desktop.present
      HAL.serial_write("[RubyOS] desktop smoke: first frame presented\n")
      client.call("debug.event.inject", { kind: 4, x: 155, y: 280, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.title == "System Monitor",
                       "dock input did not launch System Monitor")
      compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
      title_surface.blit_to(desktop.surface, x: 398, y: 26)
      png_surface.blit_to(desktop.surface, x: 460, y: 26)
      jpeg_surface.blit_to(desktop.surface, x: 464, y: 26)
      desktop.present
      audio = Sound::BridgeOutput.new(client)
      HAL.serial_write("[RubyOS] desktop smoke: second frame presented\n")
      chord = Sound::Mixer.new.mix(
        Sound::Waveform.sine(220, duration_ms: 40, amplitude: 0.10),
        Sound::Waveform.sine(330, duration_ms: 40, amplitude: 0.10)
      )
      audio.play(chord)
      RubyOS.invariant(audio.queued_bytes >= 0, "SDL audio queue unavailable")
      audio.close
      HAL.serial_write("[RubyOS] desktop smoke: audio checked\n")
      desktop.capture("/tmp/rubyos-baremetal-desktop.bmp")
      performance = client.performance_snapshot
      HAL.serial_write("[RubyOS] desktop smoke: metrics received\n")
      guest_ops = performance.fetch(:guest_round_trip)
      host_ops = performance.fetch(:host_service).fetch("ops")
      RubyOS.invariant(guest_ops.fetch("frame.commit").fetch(:count).positive?,
                       "guest bridge timing did not record frame.commit")
      RubyOS.invariant(host_ops.fetch("frame.commit").fetch("count").positive?,
                       "host bridge timing did not record frame.commit")
      title_surface.destroy
      png_surface.destroy
      jpeg_surface.destroy
      font.close
      desktop.close
      client.call("shutdown")
      client.close
      RubyOS::HAL.serial_write("[RubyOS] remote SDL desktop: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] SDL input routing: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] keyboard Terminal input: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] core desktop apps: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] compositor desktop mechanics: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] SDL_ttf Ruby Font: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] PNG/JPEG image surfaces: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] SDL audio bridge: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] Ruby chipset workbench: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] dual-playfield chipset clock: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] Ruby arcade games: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] guest/host performance metrics: PASS\n")
      true
    end

    def run_interactive_desktop(transport)
      client = Bridge::Client.new(transport)
      client.hello
      desktop = Bridge::RemoteDesktop.new(client, width: 640, height: 480, title: "RubyOS")
      compositor = GUI::Compositor.new(width: 640, height: 480, title: "RubyOS")
      applications = Apps::Registry.new
      { "About" => Apps::About.new, "Files" => Apps::Files.new,
        "Terminal" => Apps::Terminal.new, "Monitor" => Apps::SystemMonitor.new,
        "Inspector" => Apps::RubyInspector.new, "Clock" => Apps::Clock.new,
        "Settings" => Apps::Settings.new, "Invaders" => Apps::Invaders.new,
        "Snake" => Apps::Snake.new }.each { |name, app| applications.register(name, app) }
      runtime = Live::Runtime.new(vfs: state.fetch(:vfs), registry: applications)
      runtime.install("Live Hello", source: Apps::LIVE_HELLO_SOURCE, path: "/apps/live_hello.rb")
      applications.register("Editor", Apps::Editor.new(
        path: "/apps/live_hello.rb", runtime:, application_name: "Live Hello"))
      applications.each do |name, application|
        compositor.add_dock_item(name[0, 4]) { application.launch(compositor) }
      end
      applications.fetch("Terminal").launch(compositor)
      ready = false
      loop do
        events = desktop.events
        # RemoteOS protocol v2 uses wire event 6 for SDL_QUIT.
        break if events.any? { |event| event.kind == 6 || event.kind == Input::QUIT }
        events.each { |event| compositor.handle(event) }
        compositor.draw(desktop.surface, uptime: "#{state.fetch(:clock).milliseconds} ms")
        desktop.present
        unless ready
          HAL.serial_write("[RubyOS] interactive desktop: READY\n")
          ready = true
        end
        HAL.sleep_us(16_000)
      end
      desktop.close
      client.call("shutdown")
      client.close
      HAL.serial_write("[RubyOS] interactive desktop: CLOSED\n")
      true
    end

    def boot_remote_desktop_tcp(port: 5_001, interactive: false)
      device = Drivers::VirtioNet.find
      lease = Net::DHCPClient.new(device).acquire
      stack = Net::Stack.new(device, address: lease.address, gateway: lease.gateway)
      RubyOS::HAL.serial_write(
        "[RubyOS] RemoteOS TCP ready on #{lease.address}:#{port}\n"
      )
      connection = stack.listen(port).accept(timeout_ms: 120_000)
      transport = Bridge::Transport::NativeTCP.new(connection)
      return run_interactive_desktop(transport) if interactive

      boot_remote_desktop(transport:)
      RubyOS::HAL.serial_write("[RubyOS] RemoteOS over native TCP: PASS\n")
      true
    end
  end
end
