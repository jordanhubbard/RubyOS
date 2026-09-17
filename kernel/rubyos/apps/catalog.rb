# frozen_string_literal: true

module RubyOS
  module Apps
    module Catalog
      module_function

      def build(kernel: RubyOS::Kernel)
        registry = Registry.new
        register_apps(registry, kernel)
        register_demos(registry, kernel)
        register_games(registry, kernel)
        registry.register(
          "Launcher", Launcher.new(kernel:, registry:),
          description: "Browse every installed application, Ruby demo, and game",
          dock_label: "Apps"
        )
        registry
      end

      def register_apps(registry, kernel)
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
