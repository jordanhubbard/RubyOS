# frozen_string_literal: true

module RubyOS
  module Apps
    module Catalog
      DEFAULT_DOCK = %w[Launcher Files Terminal Editor Inspector Monitor].freeze
      module_function

      def build(kernel: RubyOS::Kernel)
        registry = Registry.new
        shortcuts = ShortcutStore.new(vfs: kernel.state.fetch(:vfs))
        register_apps(registry, kernel, shortcuts:)
        register_demos(registry, kernel)
        register_games(registry, kernel)
        registry.register(
          "Launcher", Launcher.new(kernel:, registry:),
          description: "Browse every installed application, Ruby demo, and game",
          dock_label: "Apps"
        )
        registry
      end

      def install_desktop(compositor, registry, file_transfer: nil)
        launch = ->(name) { registry.fetch(name).launch(compositor) }
        category_menu = lambda do |title, category|
          GUI::Menu.new(title:, items: registry.entries(category:).map do |entry|
            GUI::MenuItem.command(entry.description.empty? ? entry.name : entry.description) do
              entry.application.launch(compositor)
            end
          end)
        end
        compositor.set_system_menus([
          GUI::Menu.new(title: "RubyOS", items: [
            GUI::MenuItem.command("About RubyOS") { launch.call("About") },
            GUI::MenuItem.command("Keyboard Shortcuts", shortcut: "F1") { launch.call("Keybindings") },
            GUI::MenuItem.command("Applications", shortcut: "F2") { launch.call("Launcher") },
            GUI::MenuItem.command("Ruby Inspector") { launch.call("Inspector") },
            GUI::MenuItem.separator,
            GUI::MenuItem.command("Ruby #{RUBY_VERSION}", enabled: false)
          ]),
          category_menu.call("Apps", :app),
          category_menu.call("Demos", :demo),
          category_menu.call("Games", :game)
        ])
        compositor.set_desktop_context_menu([
          GUI::MenuItem.command("Applications", shortcut: "F2") { launch.call("Launcher") },
          GUI::MenuItem.command("Terminal", shortcut: "F3") { launch.call("Terminal") },
          GUI::MenuItem.command("Files", shortcut: "F4") { launch.call("Files") }
        ])
        compositor
          .bind_key(Input::KEY_F1, name: "Keyboard Shortcuts") { launch.call("Keybindings") }
          .bind_key(Input::KEY_F2, name: "Applications") { launch.call("Launcher") }
          .bind_key(Input::KEY_F3, name: "Terminal") { launch.call("Terminal") }
          .bind_key(Input::KEY_F4, name: "Files") { launch.call("Files") }
          .bind_key(119, mods: Input::MOD_CTRL,
                    name: "Close Window") { compositor.close(compositor.focused_window) }
        registry.fetch("Keybindings").restore(compositor)
        install_dock(compositor, registry)
        install_file_transfer(compositor, registry, file_transfer) if file_transfer
        compositor
      end

      def install_file_transfer(compositor, registry, transfer)
        compositor.install_file_transfer(transfer) do |event|
          files = registry.fetch("Files")
          window = compositor.windows.reverse.find { |candidate| candidate.application.equal?(files) }
          if window
            window.minimized = false
            compositor.focus(window)
          else
            files.launch(compositor)
          end
          files.navigate("/home")
          files.receive_drop(event, directory: "/home")
        end
      end

      def install_dock(compositor, registry)
        store = DockStore.new(vfs: registry.fetch("Keybindings").store.vfs)
        saved = store.load
        pinned = saved.nil? ? DEFAULT_DOCK : saved
        entries = registry.entries
        order = (pinned + entries.map(&:name)).uniq
        entries.sort_by { |entry| order.index(entry.name) }.each do |entry|
          compositor.register_dock_item(
            entry.name, entry.dock_label, application: entry.application,
            pinned: pinned.include?(entry.name)
          ) { entry.application.launch(compositor) }
        end
        compositor.on_dock_change { |names| store.save(names) }
      end

      def register_apps(registry, kernel, shortcuts:)
        entries = [
          ["About", About, "RubyOS version, runtime, and design identity", "Info"],
          ["Files", Files, "Browse the VFS and open files in the Ruby editor", "Files"],
          ["Terminal", Terminal, "RubyOS commands and live Ruby evaluation", "Term"],
          ["Monitor", SystemMonitor, "Tasks, scheduler, memory, and CPU state", "Mon"],
          ["Inspector", RubyInspector, "Fibers, drivers, ancestors, and live heap", "Ruby"],
          ["Image", ImageViewer, "Ruby-generated bitmap and image surface viewer", "Image"],
          ["Media", MediaWorkbench, "Ruby bitmap, scene, sound, and motion workbench", "Media"],
          ["Clock", Clock, "Monotonic and session time", "Clock"],
          ["Settings", Settings, "Desktop preferences", "Set"]
        ]
        entries.each do |name, type, description, dock_label|
          registry.register(name, type.new(kernel:), description:, dock_label:)
        end
        registry.register("Keybindings", Keybindings.new(kernel:, store: shortcuts),
                          description: "Inspect, persist, and rebind global desktop shortcuts",
                          dock_label: "Keys")
      end

      def register_demos(registry, kernel)
        registry.register("Enumerable Lab", EnumerableLab.new(kernel:), category: :demo,
                          description: "Step through select, map, slices, and reduce",
                          dock_label: "Enum")
        registry.register("Fiber Lab", FiberLab.new(kernel:), category: :demo,
                          description: "Resume a Fiber across explicit yield points",
                          dock_label: "Fiber")
        registry.register("Pattern Lab", PatternLab.new(kernel:), category: :demo,
                          description: "Destructure input and device events with case/in",
                          dock_label: "Match")
        registry.register("Life", LifeDemo.new(kernel:), category: :demo,
                          description: "Evolve cellular neighbors with flat_map and Hash#tally",
                          dock_label: "Life")
        registry.register("Complex Plane", MandelbrotDemo.new(kernel:), category: :demo,
                          description: "Explore Mandelbrot iteration with Ruby Complex values",
                          dock_label: "Cmplx")
        registry.register("Spirograph", SpirographDemo.new(kernel:), category: :demo,
                          description: "Draw parametric curves with Range#map and each_with_index",
                          dock_label: "Spiro")
        registry.register("Paint", PaintDemo.new(kernel:), category: :demo,
                          description: "Paint interactively with pointer capture and mutable Bitmap lines",
                          dock_label: "Paint")
        registry.register("Lazy Starfield", LazyStarfieldDemo.new(kernel:), category: :demo,
                          description: "Animate immutable Data stars through a lazy Enumerator stream",
                          dock_label: "Stars")
        registry.register("Plasma", PalettePlasmaDemo.new(kernel:), category: :demo,
                          description: "Animate palette fields with Enumerable lookup tables",
                          dock_label: "Plasm")
        registry.register("Event Scope", EventScopeDemo.new(kernel:), category: :demo,
                          description: "Pattern-match live keyboard and pointer events",
                          dock_label: "Event")
      end

      def register_games(registry, kernel)
        registry.register("Invaders", Invaders.new(kernel:), category: :game,
                          description: "Ruby objects, collision detection, and PCM cues",
                          dock_label: "Inv")
        registry.register("Snake", Snake.new(kernel:), category: :game,
                          description: "Enumerable grid state and keyboard steering",
                          dock_label: "Snake")
        registry.register("Maze", Maze.new(kernel:), category: :game,
                          description: "Hash-backed gems and immutable Data ghosts",
                          dock_label: "Maze")
        registry.register("Raiders", Raiders.new(kernel:), category: :game,
                          description: "Immutable Data formations and diving raiders",
                          dock_label: "Raid")
        registry.register("Defender", Defender.new(kernel:), category: :game,
                          description: "Circular Ruby world with rescue, abduction, radar, and bombs",
                          dock_label: "Def")
      end
    end
  end
end
