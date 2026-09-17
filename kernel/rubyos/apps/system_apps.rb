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
      attr_reader :path

      def initialize(path: "/", **options)
        super(**options)
        @path = path
      end

      def build_window
        window_x, window_y = spacious_desktop? ? [110, 42] : [170, 38]
        window_width, window_height = spacious_desktop? ? [420, 300] : [300, 190]
        content_width = window_width - 36
        list_height = window_height - 118
        @window = GUI::Window.new("Files", x: window_x, y: window_y,
                                  width: window_width, height: window_height,
                                  background: 0x151c29)
        @path_label = @window.add(GUI::Label.new(path, x: 8, y: 6,
                                                 width: content_width - 120,
                                                 color: 0xffffff))
        @window.add(GUI::Button.new("Up", x: content_width - 104, y: 0,
                                    width: 48, height: 24,
                                    action: ->(*) { go_up }))
        @window.add(GUI::Button.new("Home", x: content_width - 50, y: 0,
                                    width: 56, height: 24,
                                    action: ->(*) { navigate("/home") }))
        @list = @window.add(GUI::ListView.new(x: 8, y: 34, width: content_width,
                                              height: list_height,
                                              background: 0x1d2535,
                                              on_activate: method(:activate_entry),
                                              on_cancel: method(:go_up)))
        @status = @window.add(GUI::Label.new("", x: 8, y: 44 + list_height,
                                             width: content_width,
                                             height: 22, color: 0xa8d8ff))
        refresh
        @window.focus_child(@list)
        @window
      end

      def navigate(destination)
        kernel.state.fetch(:vfs).readdir(destination)
        @path = normalize(destination)
        refresh
        true
      rescue FS::Error => error
        @status.text = "#{error.class}: #{error.message}"
        @status.color = 0xff668a
        @status.invalidate
        false
      end

      def go_up(*)
        return false if path == "/"

        parts = path.split("/").reject(&:empty?)
        parts.pop
        navigate("/" + parts.join("/"))
      end

      def activate_entry(item)
        return navigate(item.fetch(:path)) if item.fetch(:kind) == :directory

        stat = kernel.state.fetch(:vfs).stat(item.fetch(:path))
        @status.text = "Opening #{item.fetch(:label)}  -  #{stat.size} bytes"
        @status.color = 0xc3e88d
        @status.invalidate
        Editor.new(path: item.fetch(:path)).launch(@compositor)
        true
      end

      private

      def refresh
        vfs = kernel.state.fetch(:vfs)
        entries = vfs.readdir(path).reject { |entry| [".", ".."].include?(entry) }
        items = entries.sort.map do |entry|
          entry_path = path == "/" ? "/#{entry}" : "#{path}/#{entry}"
          { label: entry, path: entry_path, kind: vfs.stat(entry_path).type }
        end
        @window.title = "Files - #{path}"
        @path_label.text = path
        @list.replace(items)
        @status.text = "#{items.length} item#{items.length == 1 ? '' : 's'}  |  arrows + Enter  |  Backspace: up"
        @status.color = 0xa8d8ff
        @window.invalidate
      end

      def normalize(value)
        parts = []
        String(value).split("/").each do |part|
          next if part.empty? || part == "."
          part == ".." ? parts.pop : parts << part
        end
        "/" + parts.join("/")
      end
    end

    class Terminal < Application
      attr_reader :last_result

      class OutputBuffer
        attr_reader :string

        def initialize = (@string = +"")
        def clear = @string.clear
        def write(value) = (@string << String(value))
        def puts(value = "") = (@string << String(value) << "\n")
      end

      def build_window
        window_x, window_y = spacious_desktop? ? [72, 88] : [54, 40]
        window_width, window_height = spacious_desktop? ? [460, 270] : [400, 210]
        content_width = window_width - 36
        transcript_height = window_height - 98
        prompt_y = window_height - 74
        @output = OutputBuffer.new
        @shell = Shell.new(output: @output)
        @transcript = ["RubyOS console", "Commands and Ruby expressions share this prompt. Type help to begin."]
        GUI::Window.new("Terminal", x: window_x, y: window_y,
                        width: window_width, height: window_height,
                        background: 0x10131a).tap do |window|
          @result_label = window.add(GUI::Label.new(@transcript.join("\n"), x: 8, y: 8,
                                                     width: content_width,
                                                     height: transcript_height,
                                                     wrap: true, color: 0xc3e88d))
          window.add(GUI::Label.new("rubyos>", x: 8, y: prompt_y, width: 64,
                                    color: 0xffd866))
          @input = window.add(GUI::TextInput.new(x: 72, y: prompt_y - 6,
                                                 width: window_width - 100, height: 28,
                                                 background: 0x211a29,
                                                 on_submit: method(:evaluate)))
        end
      end

      def evaluate(source)
        source = String(source).strip
        return nil if source.empty?

        @output.clear
        @shell.execute_line(source)
        @last_result = @output.string.sub(/\n\z/, "")
        @transcript << "rubyos> #{source}"
        @transcript.concat(@last_result.split("\n")) unless @last_result.empty?
        visible_rows = [(@result_label.height / GUI::Label::LINE_HEIGHT), 1].max
        @transcript = @transcript.last(visible_rows)
        @result_label.text = @transcript.join("\n")
        @input.replace("")
        @result_label.invalidate
        @last_result
      end
    end

    class SystemMonitor < Application
      def build_window
        tasks = kernel.state.fetch(:scheduler).tasks
        uptime = kernel.state.fetch(:clock).milliseconds
        memory = kernel.state.fetch(:memory).snapshot
        cpus = Concurrency.stats
        GUI::Window.new("System Monitor", x: 150, y: 36, width: 286, height: 132,
                        background: 0x202336).tap do |window|
          window.add(GUI::Label.new("Ruby tasks: #{tasks.length}", x: 0, y: 0, color: 0xf7c978))
          window.add(GUI::Label.new("Uptime: #{uptime} ms", x: 0, y: 24, color: 0xa8d8ff))
          window.add(GUI::Label.new("Scheduler: Fiber", x: 0, y: 48, color: 0xc3e88d))
          window.add(GUI::Label.new("Heap: #{memory.used_bytes / 1024} / #{memory.total_bytes / 1024} KiB",
                                    x: 0, y: 72, color: 0xe8b4ff))
          window.add(GUI::Label.new("CPUs: #{cpus.online}/#{cpus.cpus}", x: 0, y: 96, color: 0x89ddff))
        end
      end
    end

    class Clock < Application
      def build_window
        clock = kernel.state.fetch(:clock)
        GUI::Window.new("RubyOS Clock", x: 174, y: 72, width: 180, height: 96,
                        background: 0x171a24).tap do |window|
          window.add(GUI::Label.new(clock.format_hms, x: 36, y: 10, color: 0xffd866))
          window.add(GUI::Label.new("monotonic + session time", x: 0, y: 38, color: 0xa8d8ff))
        end
      end
    end

    class Settings < Application
      attr_reader :animations

      def initialize(**options)
        super
        @animations = true
      end

      def toggle_animations(*)
        @animations = !animations
        @status.text = "Animations: #{animations ? 'on' : 'off'}"
        @status.invalidate
      end

      def build_window
        GUI::Window.new("Settings", x: 126, y: 58, width: 230, height: 120,
                        background: 0x202336).tap do |window|
          @status = window.add(GUI::Label.new("Animations: on", x: 4, y: 4, color: 0xe8dff5))
          window.add(GUI::Button.new("Toggle", x: 4, y: 36, width: 72, height: 24,
                                     background: 0x553184, action: method(:toggle_animations)))
        end
      end
    end

    class Editor < Application
      attr_reader :path, :content, :reload_error

      def initialize(path: "/home/welcome.txt", runtime: nil,
                     application_name: nil, **)
        super(**)
        @path = path
        @runtime = runtime
        @application_name = application_name
        @content = kernel.state.fetch(:vfs).read_file(path)
      rescue FS::NotFound
        @content = +""
      end

      def save(text)
        @content = String(text)
        kernel.state.fetch(:vfs).write_file(path, @content)
        self
      end

      def reload(*)
        raise RubyOS::Error, "editor is not attached to a live application" unless @runtime
        @runtime.reload(@application_name, path:)
        @reload_error = nil
        @status.text = "Reloaded #{@application_name}"
        @status.color = 0xc3e88d
        @status.invalidate
        true
      rescue Exception => error
        @reload_error = error
        @status.text = "#{error.class}: #{error.message}"[0, 48]
        @status.color = 0xff668a
        @status.invalidate
        false
      end

      def build_window
        GUI::Window.new("Editor - #{path}", x: 72, y: 54, width: 350, height: 164,
                        background: 0x171a24).tap do |window|
          window.add(GUI::TextInput.new(text: content, x: 0, y: 0, width: 326, height: 88,
                                        background: 0x11151e, multiline: true,
                                        on_change: method(:save)))
          if @runtime
            window.add(GUI::Button.new("Reload Ruby", x: 0, y: 92, width: 104,
                                       height: 24, background: 0x553184,
                                       action: method(:reload)))
            @status = window.add(GUI::Label.new("Transactional reload ready",
                                                x: 112, y: 96,
                                                color: 0xa8d8ff))
          end
        end
      end
    end

    LIVE_HELLO_SOURCE = <<~'RUBY'
      class App < RubyOS::Apps::Application
        def build_window
          RubyOS::GUI::Window.new("Live Ruby", x: 92, y: 72,
                                   width: 260, height: 112,
                                   background: 0x241631).tap do |window|
            window.add(RubyOS::GUI::Label.new(
              "Edit /apps/live_hello.rb",
              x: 4, y: 4, color: 0xffd866
            ))
            window.add(RubyOS::GUI::Label.new(
              "A fresh class is swapped in on reload",
              x: 4, y: 32, color: 0xc3e88d
            ))
          end
        end
      end
    RUBY

    class RubyInspector < Application
      def build_window
        @window = GUI::Window.new("Ruby Inspector", x: 94, y: 40, width: 452, height: 308,
                                  background: 0x151522)
        @window.add(GUI::Label.new("RUNTIME", x: 8, y: 4, width: 100, color: 0x8f7cff))
        @fibers = @window.add(GUI::Label.new("", x: 8, y: 28, width: 196,
                                             color: 0x78dce8))
        @drivers = @window.add(GUI::Label.new("", x: 220, y: 28, width: 196,
                                              color: 0xa9dc76))
        @window.add(GUI::Label.new("OBJECT MODEL", x: 8, y: 62, width: 130,
                                   color: 0x8f7cff))
        @ancestors = @window.add(GUI::Label.new("", x: 8, y: 86, width: 416,
                                                height: 42, wrap: true, color: 0xffd866))
        @window.add(GUI::Label.new("LIVE HEAP", x: 8, y: 136, width: 100,
                                   color: 0x8f7cff))
        @heap_meters = 3.times.map do |index|
          @window.add(GUI::Meter.new(value: 0, maximum: 1, x: 8,
                                     y: 160 + index * 28, width: 416, height: 22,
                                     color: [0x7048a8, 0x536d9b, 0x3e8178].fetch(index)))
        end
        @window.add(GUI::Button.new("Refresh", x: 340, y: 250, width: 84, height: 24,
                                    action: method(:refresh)))
        refresh
        @window
      end

      def refresh(*)
        state = kernel.state
        fibers = Introspection.fibers(state.fetch(:scheduler))
        drivers = Introspection.drivers(state.fetch(:bus))
        shape = Introspection.class_shape(GUI::View)
        heap = Introspection.heap_summary(limit: 3)
        states = fibers.map { |fiber| fiber[:state] }.tally.map { |name, count| "#{count} #{name}" }
        @fibers.text = "Fibers  #{fibers.length}  (#{states.join(', ')})"
        @drivers.text = "Drivers  #{drivers.count { |driver| driver[:bound] }} / #{drivers.length} bound"
        @ancestors.text = shape[:ancestors].first(4).join("  <  ")
        maximum = [heap.map(&:last).max || 1, 1].max
        @heap_meters.each_with_index do |meter, index|
          name, count = heap.fetch(index, ["-", 0])
          meter.maximum = maximum
          meter.value = count
          meter.label = "#{name}   #{count}"
        end
        @window.invalidate
        true
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

    class CanvasPreview < GUI::View
      def initialize(bitmap, scale: 5, **options)
        super(**options)
        @bitmap = bitmap
        @scale = scale
      end

      def draw(surface)
        pixels = @bitmap.raster
        @bitmap.height.times do |row|
          @bitmap.width.times do |column|
            surface.fill_rect(x + column * @scale, y + row * @scale,
                              @scale, @scale, pixels[row * @bitmap.width + column])
          end
        end
      end
    end

    class MediaWorkbench < Application
      def build_view
        view = Media::Bitmap.new(32, 16)
        16.times do |row|
          view.rect(0, row, 32, 1, color: [0x17243a, 0x203951, 0x28516a, 0x357489][row / 4])
        end
        view.rect(6, 3, 10, 9, color: 0x51d6c5)
        view.rect(14, 6, 11, 7, color: 0xffce73)
        view
      end

      def build_window
        GUI::Window.new("Ruby Media Studio", x: 138, y: 56, width: 196, height: 140,
                        background: 0x0c0912).tap do |window|
          window.add(CanvasPreview.new(build_view, x: 2, y: 0, width: 160, height: 80))
          window.add(GUI::Label.new("Scenes, sound, motion", x: 2, y: 88, color: 0xe8dff5))
        end
      end
    end
  end
end
