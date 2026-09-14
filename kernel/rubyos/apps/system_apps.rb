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

    class Editor < Application
      attr_reader :path, :content

      def initialize(path: "/home/welcome.txt", **)
        super(**)
        @path = path
        @content = kernel.state.fetch(:vfs).read_file(path)
      rescue FS::NotFound
        @content = +""
      end

      def save(text)
        @content = String(text)
        kernel.state.fetch(:vfs).write_file(path, @content)
        self
      end

      def build_window
        GUI::Window.new("Editor - #{path}", x: 72, y: 54, width: 350, height: 164,
                        background: 0x171a24).tap do |window|
          content.lines.first(4).each_with_index do |line, index|
            window.add(GUI::Label.new(line.chomp, x: 0, y: index * 22, color: 0xe7e1ed))
          end
          window.add(GUI::Label.new("Ruby String -> VFS#write_file", x: 0, y: 94, color: 0xc3e88d))
        end
      end
    end

    class PixelArt < GUI::View
      def draw(surface)
        super
        colors = [0xff668a, 0xffd866, 0x78dce8, 0xa9dc76, 0xab9df2]
        5.times do |row|
          8.times do |column|
            color = colors[(row + column * 2) % colors.length]
            surface.fill_rect(x + column * 20, y + row * 14, 18, 12, color)
          end
        end
      end
    end

    class ImageViewer < Application
      def build_window
        GUI::Window.new("Image Viewer", x: 116, y: 48, width: 220, height: 150,
                        background: 0x10151f).tap do |window|
          window.add(PixelArt.new(x: 10, y: 4, width: 160, height: 70))
          window.add(GUI::Label.new("Ruby-generated pixels", x: 10, y: 84, color: 0xe8dff5))
        end
      end
    end
  end
end
