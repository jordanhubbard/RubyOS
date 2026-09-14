# frozen_string_literal: true

module RubyOS
  module Apps
    class About < Application
      def build_window
        GUI::Window.new("About RubyOS", x: 28, y: 42, width: 250, height: 142,
                        background: 0x21182f).tap do |window|
          window.add(GUI::Label.new("RubyOS", x: 0, y: 0, color: 0xffd866))
          window.add(GUI::Label.new("Ruby is the kernel", x: 0, y: 24, color: 0xffffff))
          window.add(GUI::Label.new("CRuby 4 + Prism", x: 0, y: 48, color: 0x9cdcfe))
          window.add(GUI::Label.new("Objects all the way down", x: 0, y: 72, color: 0xc3e88d))
        end
      end
    end

    class Files < Application
      def build_window
        entries = kernel.state.fetch(:vfs).readdir("/").reject { |entry| [".", ".."].include?(entry) }
        GUI::Window.new("Files - /", x: 196, y: 68, width: 254, height: 170,
                        background: 0x1d2535).tap do |window|
          entries.each_with_index do |entry, index|
            window.add(GUI::Label.new("[DIR] #{entry}", x: 4, y: index * 24, color: 0xb9dcff))
          end
        end
      end
    end

    class Terminal < Application
      def build_window
        GUI::Window.new("Ruby Console", x: 54, y: 150, width: 336, height: 106,
                        background: 0x121017).tap do |window|
          window.add(GUI::Label.new("rubyos> 6.times.map { _1**2 }", x: 0, y: 0, color: 0xe8dff5))
          window.add(GUI::Label.new("=> [0, 1, 4, 9, 16, 25]", x: 0, y: 24, color: 0xc3e88d))
        end
      end
    end

    class SystemMonitor < Application
      def build_window
        tasks = kernel.state.fetch(:scheduler).tasks
        uptime = kernel.state.fetch(:clock).milliseconds
        GUI::Window.new("System Monitor", x: 150, y: 36, width: 286, height: 132,
                        background: 0x202336).tap do |window|
          window.add(GUI::Label.new("Ruby tasks: #{tasks.length}", x: 0, y: 0, color: 0xf7c978))
          window.add(GUI::Label.new("Uptime: #{uptime} ms", x: 0, y: 24, color: 0xa8d8ff))
          window.add(GUI::Label.new("Scheduler: Fiber", x: 0, y: 48, color: 0xc3e88d))
        end
      end
    end
  end
end
