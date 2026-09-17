# frozen_string_literal: true

module RubyOS
  module Apps
    module Catalog
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

      def install_desktop(compositor, registry)
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
        compositor
          .bind_key(Input::KEY_F1, name: "Keyboard Shortcuts") { launch.call("Keybindings") }
          .bind_key(Input::KEY_F2, name: "Applications") { launch.call("Launcher") }
          .bind_key(Input::KEY_F3, name: "Terminal") { launch.call("Terminal") }
          .bind_key(Input::KEY_F4, name: "Files") { launch.call("Files") }
          .bind_key(119, mods: Input::MOD_CTRL,
                    name: "Close Window") { compositor.close(compositor.focused_window) }
        registry.fetch("Keybindings").restore(compositor)
        compositor
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
      end

      def register_games(registry, kernel)
        registry.register("Invaders", Invaders.new(kernel:), category: :game,
                          description: "Ruby objects, collision detection, and PCM cues",
                          dock_label: "Inv")
        registry.register("Snake", Snake.new(kernel:), category: :game,
                          description: "Enumerable grid state and keyboard steering",
                          dock_label: "Snake")
      end
    end
  end
end
