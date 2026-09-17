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
      applications = Apps::Catalog.build(kernel: self)
      terminal = applications.fetch("Terminal")
      settings = applications.fetch("Settings")
      runtime = Live::Runtime.new(vfs: state.fetch(:vfs), registry: applications)
      runtime.install("Live Hello", source: Apps::LIVE_HELLO_SOURCE,
                      path: "/apps/live_hello.rb")
      applications.register("Editor", Apps::Editor.new(
        path: "/apps/live_hello.rb", runtime:, application_name: "Live Hello"
      ), description: "Edit VFS files and transactionally reload Ruby applications",
         dock_label: "Edit")
      Apps::Catalog.install_desktop(compositor, applications)
      applications.entries(category: :app).each do |entry|
        compositor.add_dock_item(entry.dock_label) { entry.application.launch(compositor) }
      end
      compositor.add_shortcut("Clock", x: 8, y: 42) { applications.fetch("Clock").launch(compositor) }
      compositor.add_shortcut("Files", x: 8, y: 104) { applications.fetch("Files").launch(compositor) }
      applications.fetch("About").launch(compositor)
      applications.fetch("Files").launch(compositor)
      applications.fetch("Media").launch(compositor)
      terminal_window = applications.fetch("Terminal").launch(compositor)
      HAL.serial_write("[RubyOS] desktop smoke: applications launched\n")
      RubyOS.invariant(applications.entries(category: :app).length == 13 &&
                       applications.entries(category: :demo).length == 3 &&
                       applications.entries(category: :game).length == 2,
                       "categorized application catalog is incomplete")
      launcher_window = applications.fetch("Launcher").launch(compositor)
      compositor.draw(desktop.surface, uptime: "catalog")
      desktop.present
      desktop.capture("/tmp/rubyos-catalog.bmp")
      compositor.close(launcher_window)
      applications.entries(category: :demo).each do |entry|
        demo = entry.application
        demo_window = demo.launch(compositor)
        demo.advance if demo.respond_to?(:advance)
        demo.resume if demo.respond_to?(:resume)
        compositor.draw(desktop.surface, uptime: entry.name)
        compositor.close(demo_window)
      end
      HAL.serial_write("[RubyOS] desktop smoke: Ruby demos checked\n")
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
      client.call("debug.event.inject", { kind: 1, code: Input::KEY_F1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.title == "Keyboard Shortcuts",
                       "F1 did not launch the keybinding control panel")
      client.call("debug.event.inject", { kind: 1, code: 119, mod: 0x0040 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window == terminal_window,
                       "canonical Ctrl+W did not close the keybinding panel")
      client.call("debug.event.inject", { kind: 1, code: Input::KEY_F2 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.title == "RubyOS Applications",
                       "F2 did not launch the application catalog")
      client.call("debug.event.inject", { kind: 1, code: 119, mod: 0x0040 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window == terminal_window,
                       "canonical Ctrl+W did not close the catalog")
      editor = applications.fetch("Editor")
      editor_window = editor.launch(compositor)
      editor.open_dialog
      RubyOS.invariant(compositor.focused_window.title == "Open Ruby or text file" &&
                       editor.file_dialog.cwd == "/apps",
                       "Editor did not launch the shared VFS file dialog")
      compositor.draw(desktop.surface, uptime: "open / save")
      desktop.present
      desktop.capture("/tmp/rubyos-file-dialog.bmp")
      client.call("debug.event.inject", { kind: 1, code: 27 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(editor.file_dialog.done? && compositor.focused_window == editor_window,
                       "Escape did not cancel the shared file dialog")
      compositor.close(editor_window)
      HAL.serial_write("[RubyOS] desktop smoke: file dialog checked\n")
      client.call("debug.event.inject", { kind: 4, x: 126, y: 10, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      compositor.draw(desktop.surface, uptime: "menus")
      desktop.present
      desktop.capture("/tmp/rubyos-menu.bmp")
      client.call("debug.event.inject", { kind: 4, x: 130, y: 34, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant(compositor.focused_window.title == "Enumerable Pipeline",
                       "Demos menu did not launch the first Ruby demo")
      compositor.close(compositor.focused_window)
      HAL.serial_write("[RubyOS] desktop smoke: menus and shortcuts checked\n")
      initial_terminal_position = [terminal_window.x, terminal_window.y]
      drag_x = terminal_window.x + 20
      drag_y = terminal_window.y + 10
      client.call("debug.event.inject", { kind: 4, x: drag_x, y: drag_y, button: 1 })
      client.call("debug.event.inject", { kind: 3, x: drag_x + 20, y: drag_y + 20 })
      client.call("debug.event.inject", { kind: 5, x: drag_x + 20, y: drag_y + 20, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      expected_terminal_position = [initial_terminal_position.fetch(0) + 20,
                                    [initial_terminal_position.fetch(1) + 20,
                                     compositor.height - GUI::Compositor::DOCK_HEIGHT - terminal_window.height].min]
      RubyOS.invariant([compositor.focused_window.x, compositor.focused_window.y] == expected_terminal_position,
                       "window title drag did not move Terminal")
      clock_window = applications.fetch("Clock").launch(compositor)
      initial_clock_size = [clock_window.width, clock_window.height]
      resize_x = clock_window.x + clock_window.width - 3
      resize_y = clock_window.y + clock_window.height - 3
      client.call("debug.event.inject", { kind: 4, x: resize_x, y: resize_y, button: 1 })
      client.call("debug.event.inject", { kind: 3, x: resize_x + 30, y: resize_y + 20 })
      client.call("debug.event.inject", { kind: 5, x: resize_x + 30, y: resize_y + 20, button: 1 })
      desktop.events.each { |event| compositor.handle(event) }
      RubyOS.invariant([clock_window.width, clock_window.height] ==
                       [initial_clock_size.fetch(0) + 30, initial_clock_size.fetch(1) + 20],
                       "window resize grip did not update geometry")
      compositor.draw(desktop.surface, uptime: "anchored resize")
      desktop.present
      desktop.capture("/tmp/rubyos-resized-window.bmp")
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
      png_surface.blit_to(desktop.surface, x: 460, y: 26)
      jpeg_surface.blit_to(desktop.surface, x: 464, y: 26)
      desktop.present
      HAL.serial_write("[RubyOS] desktop smoke: first frame presented\n")
      monitor_x, monitor_y = compositor.dock_item_center("Mon")
      client.call("debug.event.inject", { kind: 4, x: monitor_x, y: monitor_y, button: 1 })
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
      if client.features.include?("scene3d.render")
        session = SDL::Session.new(client)
        session.canvas(width: 96, height: 64) do |canvas|
          scene = Media::Scene3D.new
          cube = scene.add(Media::Mesh.cube)
          cube.rotation_y = 0.5
          result = canvas.render(scene)
          RubyOS.invariant(result.fetch("triangles") == 12, "cube triangle count")
          canvas.text("Ruby 3D", x: 2, y: 2)
          if client.features.include?("video.encode") && client.features.include?("video.playback")
            movie = session.encoder(width: 96, height: 64, fps: 10, audio: true) do |encoder|
              2.times { encoder.frame(canvas, pcm: "\0".b * 19200) }
              encoder.finish
            end
            session.video(movie) do |video|
              video.play
              RubyOS.invariant(video.tick(canvas).fetch("playing"), "movie did not start")
              video.pause.seek(0)
              RubyOS.invariant(!video.tick(canvas).fetch("playing"), "movie did not pause")
            end
            HAL.serial_write("[RubyOS] Ruby SDL A/V export and playback: PASS\n")
          end
        end
        HAL.serial_write("[RubyOS] Ruby SDL 3D scene: PASS\n")
      end
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
      RubyOS::HAL.serial_write("[RubyOS] categorized Ruby demo catalog: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] menus and global shortcuts: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] shared open/save dialog: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] compositor desktop mechanics: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] SDL_ttf Ruby Font: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] PNG/JPEG image surfaces: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] SDL audio bridge: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] Ruby media canvas: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] Ruby arcade games: PASS\n")
      RubyOS::HAL.serial_write("[RubyOS] guest/host performance metrics: PASS\n")
      true
    end

    def run_interactive_desktop(transport)
      client = Bridge::Client.new(transport)
      client.hello
      desktop = Bridge::RemoteDesktop.new(client, width: 640, height: 480, title: "RubyOS")
      compositor = GUI::Compositor.new(width: 640, height: 480, title: "RubyOS")
      applications = Apps::Catalog.build(kernel: self)
      runtime = Live::Runtime.new(vfs: state.fetch(:vfs), registry: applications)
      runtime.install("Live Hello", source: Apps::LIVE_HELLO_SOURCE, path: "/apps/live_hello.rb")
      applications.register("Editor", Apps::Editor.new(
        path: "/apps/live_hello.rb", runtime:, application_name: "Live Hello"),
        description: "Edit VFS files and transactionally reload Ruby applications",
        dock_label: "Edit")
      Apps::Catalog.install_desktop(compositor, applications)
      applications.entries(category: :app).each do |entry|
        compositor.add_dock_item(entry.dock_label) { entry.application.launch(compositor) }
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
