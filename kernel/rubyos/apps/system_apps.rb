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
                                                 color: 0xffffff),
                                  anchors: [:left, :right, :top], minimum_width: 48)
        @window.add(GUI::Button.new("Up", x: content_width - 104, y: 0,
                                    width: 48, height: 24,
                                    action: ->(*) { go_up }), anchors: [:right, :top])
        @window.add(GUI::Button.new("Home", x: content_width - 50, y: 0,
                                    width: 56, height: 24,
                                    action: ->(*) { navigate("/home") }), anchors: [:right, :top])
        @list = @window.add(GUI::ListView.new(x: 8, y: 34, width: content_width,
                                              height: list_height,
                                              background: 0x1d2535,
                                              on_activate: method(:activate_entry),
                                              on_back: method(:go_up)),
                            anchors: [:left, :right, :top, :bottom],
                            minimum_width: 80, minimum_height: 30)
        @status = @window.add(GUI::Label.new("", x: 8, y: 44 + list_height,
                                             width: content_width - (transfer&.export_supported? ? 78 : 0),
                                             height: 22, color: 0xa8d8ff),
                              anchors: [:left, :right, :bottom], minimum_width: 80)
        if transfer&.export_supported?
          @window.add(GUI::Button.new("Export", x: content_width - 70, y: 44 + list_height,
                                      width: 70, height: 24,
                                      action: method(:export_selected)),
                      anchors: [:right, :bottom])
        end
        @window.on_file_drop { |event| receive_drop(event) } if transfer&.import_supported?
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

      def receive_drop(event, directory: nil)
        return false unless transfer&.import_supported?

        target = unless directory
                   local_x = event.fetch("x", 0) - @window.x - 10
                   local_y = event.fetch("y", 0) - @window.y - GUI::Window::TITLE_HEIGHT - 9
                   @list.item_at(local_x, local_y)
                 end
        destination = directory || (target&.fetch(:kind, nil) == :directory ? target.fetch(:path) : path)
        show_transfer_status("Importing #{event.fetch('name', 'host file')}...")
        imported_path, count = transfer.import(
          token: event.fetch("token", 0), name: event.fetch("name", ""),
          size: event.fetch("size", -1), directory: destination
        )
        refresh
        show_transfer_status("Imported #{count} bytes: #{imported_path}")
        true
      rescue StandardError => error
        show_transfer_status("Import failed: #{error.message}", error: true)
        true
      end

      def export_selected(*)
        return false unless transfer&.export_supported?

        item = @list.selected_item
        unless item && item.fetch(:kind) == :file
          show_transfer_status("Select a file to export", error: true)
          return false
        end
        host_path, count = transfer.export(item.fetch(:path))
        show_transfer_status("Exported #{count} bytes: #{host_path}")
        true
      rescue StandardError => error
        show_transfer_status("Export failed: #{error.message}", error: true)
        false
      end

      def menus(compositor)
        file_items = [
          GUI::MenuItem.command("Export Selected",
                                enabled: !!transfer&.export_supported?) { export_selected }
        ]
        [GUI::Menu.new(title: "File", items: file_items),
         GUI::Menu.new(title: "Go", items: [
          GUI::MenuItem.command("Up", shortcut: "Backspace") { go_up },
          GUI::MenuItem.command("Home") { navigate("/home") },
          GUI::MenuItem.command("Root") { navigate("/") }
        ]), *super]
      end

      private

      def transfer = @compositor&.file_transfer

      def show_transfer_status(message, error: false)
        return unless @status

        @status.text = String(message)
        @status.color = error ? 0xff668a : 0xc3e88d
        @status.invalidate
      end

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
        count = "#{items.length} item#{items.length == 1 ? '' : 's'}"
        @status.text = transfer&.import_supported? ? "#{count}  |  drop host files" :
                                                     "#{count}  |  arrows + Enter"
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
      MAX_SCROLLBACK = 500
      MAX_HISTORY = 100

      attr_reader :last_result, :history, :transcript_view

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
        @history ||= []
        @history_index = @history.length
        GUI::Window.new("Terminal", x: window_x, y: window_y,
                        width: window_width, height: window_height,
                        background: 0x10131a).tap do |window|
          @transcript_view = window.add(GUI::TextView.new(
            text: @transcript.join("\n"), x: 8, y: 8,
            width: content_width, height: transcript_height,
            wrap: true, background: 0x0b0e14, color: 0xc3e88d
          ), anchors: [:left, :right, :top, :bottom],
             minimum_width: 80, minimum_height: 24)
          window.add(GUI::Label.new("rubyos>", x: 8, y: prompt_y, width: 64,
                                    color: 0xffd866), anchors: [:left, :bottom])
          @input = window.add(GUI::TextInput.new(x: 72, y: prompt_y - 6,
                                                 width: window_width - 100, height: 28,
                                                 background: 0x211a29,
                                                 on_submit: method(:evaluate),
                                                 on_history: method(:navigate_history)),
                              anchors: [:left, :right, :bottom], minimum_width: 56)
          window.focus_child(@input)
        end
      end

      def evaluate(source)
        source = String(source).strip
        return nil if source.empty?

        @output.clear
        @shell.execute_line(source)
        @last_result = @output.string.sub(/\n\z/, "")
        @history << source unless @history.last == source
        @history = @history.last(MAX_HISTORY)
        @history_index = @history.length
        @transcript << "rubyos> #{source}"
        @transcript.concat(@last_result.split("\n")) unless @last_result.empty?
        @transcript = @transcript.last(MAX_SCROLLBACK)
        @transcript_view.replace(@transcript.join("\n"), scroll: :end)
        @input.replace("")
        @last_result
      end

      def navigate_history(direction)
        return "" if history.empty?

        @history_index = [[@history_index + Integer(direction), 0].max, history.length].min
        @history_index == history.length ? "" : history.fetch(@history_index)
      end

      def current_command = @input&.text.to_s

      def recall(direction)
        value = navigate_history(direction)
        @input.replace(value, notify: false).move_cursor(value.each_char.count)
        true
      end

      def copy_transcript
        GUI::Clipboard.default.write(@transcript.join("\n"))
        true
      end

      def clear
        @transcript = ["RubyOS console cleared"]
        @transcript_view.replace(@transcript.first, scroll: :end)
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Terminal", items: [
          GUI::MenuItem.command("Clear") { clear },
          GUI::MenuItem.command("Show commands") { evaluate("help") },
          GUI::MenuItem.command("Copy transcript") { copy_transcript },
          GUI::MenuItem.separator,
          GUI::MenuItem.command("Previous command", shortcut: "Up") { recall(-1) },
          GUI::MenuItem.command("Next command", shortcut: "Down") { recall(1) },
          GUI::MenuItem.separator,
          GUI::MenuItem.command("Paste", shortcut: "Ctrl+V") { @input.paste },
          GUI::MenuItem.command("Select input", shortcut: "Ctrl+A") { @input.select_all }
        ]), *super]
      end
    end

    class SystemMonitor < Application
      attr_reader :refresh_count

      def build_window
        @refresh_count = 0
        @tick_count = 0
        @paused = false
        GUI::Window.new("System Monitor", x: 112, y: 38, width: 340, height: 198,
                        background: 0x151827).tap do |window|
          @summary = window.add(GUI::Label.new("", x: 8, y: 4, width: 292,
                                                height: 40, color: 0xa8d8ff))
          @task_meter = window.add(GUI::Meter.new(value: 0, maximum: 1,
                                                   x: 8, y: 48, width: 300, height: 24,
                                                   color: 0x51d6c5))
          @heap_meter = window.add(GUI::Meter.new(value: 0, maximum: 1,
                                                   x: 8, y: 80, width: 300, height: 24,
                                                   color: 0x8f7cff))
          @status = window.add(GUI::Label.new("", x: 8, y: 112, width: 190,
                                               color: 0xc3e88d))
          window.add(GUI::Button.new("Pause", x: 214, y: 108, width: 94, height: 26,
                                     action: method(:toggle_pause)))
          window.on_tick { tick }
          refresh
        end
      end

      def refresh(*)
        tasks = kernel.state.fetch(:scheduler).tasks
        uptime = kernel.state.fetch(:clock).milliseconds
        memory = kernel.state.fetch(:memory).snapshot
        cpus = Concurrency.stats
        active = tasks.count { |task| task.fiber.alive? }
        @summary.text = "Ruby scheduler  Fiber\nUptime #{uptime} ms   CPUs #{cpus.online}/#{cpus.cpus}"
        @task_meter.maximum = [tasks.length, 1].max
        @task_meter.value = active
        @task_meter.label = "Tasks  #{active} alive / #{tasks.length} total"
        @heap_meter.maximum = [memory.total_bytes, 1].max
        @heap_meter.value = memory.used_bytes
        @heap_meter.label = "Heap  #{memory.used_bytes / 1024} / #{memory.total_bytes / 1024} KiB"
        @refresh_count += 1
        @status.text = @paused ? "PAUSED" : "LIVE  sample #{@refresh_count}"
        @window&.invalidate
        true
      end

      def toggle_pause(*)
        @paused = !@paused
        @status.text = @paused ? "PAUSED" : "LIVE  sample #{@refresh_count}"
        @window.invalidate
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Monitor", items: [
          GUI::MenuItem.command("Refresh now") { refresh },
          GUI::MenuItem.command(@paused ? "Resume" : "Pause") { toggle_pause }
        ]), *super]
      end

      private

      def tick
        @tick_count += 1
        refresh if !@paused && (@tick_count % 20).zero?
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

    class Keybindings < Application
      attr_reader :store

      def initialize(store:, **options)
        super(**options)
        @store = store
        @defaults = nil
      end

      def restore(compositor)
        @compositor = compositor
        @defaults ||= compositor.keybindings.to_h { |binding| [binding.name, [binding.code, binding.mods]] }
        restored = 0
        store.load.each do |record|
          next unless @defaults.key?(record.fetch(:name))

          compositor.rebind_key(record.fetch(:name), code: record.fetch(:code),
                                mods: record.fetch(:mods))
          restored += 1
        end
        restored
      end

      def build_window
        window_x, window_y = spacious_desktop? ? [126, 52] : [50, 34]
        window_width, window_height = spacious_desktop? ? [390, 260] : [380, 210]
        content_width = window_width - 36
        list_height = window_height - 110
        window = GUI::Window.new("Keyboard Shortcuts", x: window_x, y: window_y,
                                 width: window_width, height: window_height,
                                 background: 0x151c29)
        window.add(GUI::Label.new("GLOBAL KEYMAP", x: 8, y: 4, width: 160,
                                  color: 0x8f7cff))
        @list = window.add(GUI::ListView.new(items: binding_items, x: 8, y: 30,
                                             width: content_width, height: list_height,
                                             background: 0x1d2535,
                                             on_activate: method(:capture)),
                           anchors: [:left, :right, :top, :bottom],
                           minimum_width: 80, minimum_height: 30)
        @status = window.add(GUI::Label.new("Choose a shortcut, then press its replacement",
                                            x: 8, y: 40 + list_height,
                                            width: content_width,
                                            color: 0xa8d8ff),
                              anchors: [:left, :right, :bottom], minimum_width: 80)
        window.focus_child(@list)
        window
      end

      def capture(item)
        binding = item.fetch(:binding)
        @status.text = "Press a new key for #{binding.name} (Esc cancels)"
        @status.color = 0xffd866
        @status.invalidate
        @compositor.capture_next_key do |event|
          if event.fetch("code", 0) == 27
            @status.text = "Shortcut change cancelled"
          else
            @compositor.rebind_key(binding.name, code: event.fetch("code", 0),
                                   mods: event.fetch("mods", 0))
            @list.replace(binding_items)
            persisted = save
            if persisted
              @status.text = "Saved #{binding.name}: #{chord(event.fetch('code', 0), event.fetch('mods', 0))}"
              @status.color = 0xc3e88d
            end
          end
          @status.color = 0xc3e88d if event.fetch("code", 0) == 27
          @status.invalidate
        end
        true
      end

      def save
        count = store.save(@compositor.keybindings)
        show_status("Saved #{count} shortcuts")
        count
      rescue FS::Error => error
        show_status("#{error.class}: #{error.message}", error: true)
        false
      end

      def reset_defaults
        @defaults.each do |name, (code, mods)|
          @compositor.rebind_key(name, code:, mods:)
        end
        store.clear
        @list&.replace(binding_items)
        show_status("Restored default shortcuts") if @status
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Shortcuts", items: [
          GUI::MenuItem.command("Save keymap") { save },
          GUI::MenuItem.command("Reset defaults") { reset_defaults }
        ]), *super]
      end

      private

      def show_status(message, error: false)
        @status.text = String(message)
        @status.color = error ? 0xff668a : 0xc3e88d
        @status.invalidate
      end

      def binding_items
        @compositor.keybindings.map do |binding|
          { label: "#{chord(binding.code, binding.mods).ljust(12)} #{binding.name}",
            kind: :file, binding: }
        end
      end

      def chord(code, mods)
        parts = []
        parts << "Shift" if (mods & Input::MOD_SHIFT) != 0
        parts << "Ctrl" if (mods & Input::MOD_CTRL) != 0
        parts << "Alt" if (mods & Input::MOD_ALT) != 0
        parts << "Meta" if (mods & Input::MOD_META) != 0
        key = if code.between?(Input::KEY_F1, Input::KEY_F4)
                "F#{code - Input::KEY_F1 + 1}"
              elsif code.between?(32, 126)
                code.chr.upcase
              else
                code.to_s
              end
        [*parts, key].join("+")
      end
    end

    class Editor < Application
      attr_reader :path, :content, :reload_error, :file_dialog

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
        show_status("Saved #{path}") if @status
        self
      end

      def load_path(new_path)
        contents = kernel.state.fetch(:vfs).read_file(new_path)
        @path = String(new_path)
        @content = contents
        @input&.replace(contents, notify: false)&.move_cursor(0)
        @window.title = "Editor - #{path}" if @window
        show_status("Opened #{path}") if @status
        self
      rescue FS::Error => error
        show_status("#{error.class}: #{error.message}", error: true) if @status
        false
      end

      def open_dialog(*)
        @file_dialog = GUI::FileDialog.new(
          compositor: @compositor, vfs: kernel.state.fetch(:vfs), mode: :open,
          path:, title: "Open Ruby or text file", extensions: [".rb", ".txt"],
          on_accept: method(:load_path)
        )
      end

      def save_as_dialog(*)
        @file_dialog = GUI::FileDialog.new(
          compositor: @compositor, vfs: kernel.state.fetch(:vfs), mode: :save,
          path:, title: "Save Ruby or text file",
          on_accept: method(:save_as)
        )
      end

      def save_as(new_path)
        @path = String(new_path)
        save(@input ? @input.text : content)
        @window.title = "Editor - #{path}" if @window
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
        @window = GUI::Window.new("Editor - #{path}", x: 72, y: 54, width: 350, height: 184,
                                  background: 0x171a24).tap do |window|
          @input = window.add(GUI::TextInput.new(text: content, x: 0, y: 0,
                                                  width: 326, height: 108,
                                                  background: 0x11151e, multiline: true,
                                                  on_change: method(:save)),
                              anchors: [:left, :right, :top, :bottom],
                              minimum_width: 100, minimum_height: 40)
          @input.move_cursor(0)
          if @runtime
            window.add(GUI::Button.new("Reload Ruby", x: 0, y: 112, width: 104,
                                       height: 24, background: 0x553184,
                                       action: method(:reload)), anchors: [:left, :bottom])
            @status = window.add(GUI::Label.new("Transactional reload ready",
                                                x: 112, y: 116, width: 212,
                                                color: 0xa8d8ff),
                                 anchors: [:left, :right, :bottom], minimum_width: 40)
          else
            @status = window.add(GUI::Label.new("Autosave enabled", x: 0, y: 116,
                                                width: 326, color: 0xa8d8ff),
                                 anchors: [:left, :right, :bottom], minimum_width: 80)
          end
        end
      end

      def menus(compositor)
        items = [
          GUI::MenuItem.command("Open...") { open_dialog },
          GUI::MenuItem.command("Save") { save(@input.text) },
          GUI::MenuItem.command("Save As...") { save_as_dialog },
          GUI::MenuItem.separator,
          GUI::MenuItem.command("Autosave enabled", enabled: false)
        ]
        items << GUI::MenuItem.command("Reload Ruby") { reload } if @runtime
        edit_items = [
          GUI::MenuItem.command("Cut", shortcut: "Ctrl+X") { @input.cut },
          GUI::MenuItem.command("Copy", shortcut: "Ctrl+C") { @input.copy },
          GUI::MenuItem.command("Paste", shortcut: "Ctrl+V") { @input.paste },
          GUI::MenuItem.separator,
          GUI::MenuItem.command("Select All", shortcut: "Ctrl+A") { @input.select_all }
        ]
        [GUI::Menu.new(title: "File", items:),
         GUI::Menu.new(title: "Edit", items: edit_items), *super]
      end

      private

      def show_status(message, error: false)
        @status.text = String(message)[0, 52]
        @status.color = error ? 0xff668a : 0xc3e88d
        @status.invalidate
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
      INSPECTABLE_CLASSES = [
        Object, Array, Hash, Fiber, GUI::View, GUI::Window, Application, Media::Bitmap
      ].freeze

      attr_reader :current_section, :refresh_count, :detail_view

      def build_window
        spacious = spacious_desktop?
        x, y = spacious ? [70, 38] : [20, 28]
        width, height = spacious ? [560, 350] : [440, 236]
        content_width = width - 36
        pane_height = height - 92
        sidebar_width = spacious ? 176 : 142
        @window = GUI::Window.new("Ruby Inspector", x:, y:, width:, height:,
                                  minimum_width: 390, minimum_height: 210,
                                  background: 0x111522)
        @window.add(GUI::Label.new("RUBY RUNTIME", x: 8, y: 2, width: 140,
                                   color: 0x8f7cff))
        @sections = section_items
        @section_list = @window.add(GUI::ListView.new(
          items: @sections, x: 8, y: 28, width: sidebar_width, height: pane_height,
          background: 0x1a2030, on_activate: method(:show_section)
        ), anchors: [:left, :top, :bottom], minimum_height: 80)
        @detail_view = @window.add(GUI::TextView.new(
          text: "", x: sidebar_width + 18, y: 28,
          width: content_width - sidebar_width - 18, height: pane_height,
          wrap: true, background: 0x0b1019, color: 0xc9e4ff
        ), anchors: [:left, :right, :top, :bottom],
           minimum_width: 160, minimum_height: 80)
        @status = @window.add(GUI::Label.new("", x: 8, y: 38 + pane_height,
                                             width: content_width - 98,
                                             color: 0x78dce8),
                              anchors: [:left, :right, :bottom], minimum_width: 100)
        @window.add(GUI::Button.new("Refresh", x: content_width - 82,
                                    y: 34 + pane_height, width: 82, height: 26,
                                    action: method(:refresh)), anchors: [:right, :bottom])
        @current_section = @sections.first
        @refresh_count = 0
        @tick_count = 0
        refresh
        @window.on_tick { tick }
        @window
      end

      def refresh(*)
        @heap = Introspection.heap_summary(limit: 8)
        @refresh_count += 1
        render_section
        @status.text = "LIVE  sample #{@refresh_count}  |  arrows + Enter  |  wheel scrolls detail"
        @window.invalidate
        true
      end

      def show_section(item)
        @current_section = item
        render_section(reset_scroll: true)
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Inspect", items: [
          GUI::MenuItem.command("Refresh now") { refresh },
          GUI::MenuItem.command("Copy details") { GUI::Clipboard.default.write(@detail_view.text) },
          GUI::MenuItem.command("Scroll details to end") { @detail_view.scroll_to_end }
        ]), *super]
      end

      private

      def section_items
        system = [
          { label: "Overview", key: :overview, kind: :file },
          { label: "Fibers", key: :fibers, kind: :file },
          { label: "Drivers", key: :drivers, kind: :file },
          { label: "Heap", key: :heap, kind: :file },
          { label: "Object graph", key: :graph, kind: :file }
        ]
        classes = INSPECTABLE_CLASSES.map do |type|
          { label: type.name, key: :class, type:, kind: :file }
        end
        system + classes
      end

      def render_section(reset_scroll: false)
        return unless @detail_view && current_section

        lines = case current_section.fetch(:key)
                when :overview then overview_lines
                when :fibers then fiber_lines
                when :drivers then driver_lines
                when :heap then heap_lines
                when :graph then graph_lines
                when :class then class_lines(current_section.fetch(:type))
                end
        @detail_view.replace(Array(lines).join("\n"), scroll: reset_scroll ? :start : nil)
      end

      def overview_lines
        state = kernel.state
        fibers = Introspection.fibers(state.fetch(:scheduler))
        drivers = Introspection.drivers(state.fetch(:bus))
        memory = state.fetch(:memory).snapshot
        ["Ruby #{RUBY_VERSION} / #{RUBY_PLATFORM}", "", "Runtime",
         "  Fibers: #{fibers.length}",
         "  Drivers: #{drivers.count { |driver| driver[:bound] }}/#{drivers.length} bound",
         "  Heap: #{memory.used_bytes / 1024}/#{memory.total_bytes / 1024} KiB", "",
         "Heap leaders", *heap_lines.first(5).map { |line| "  #{line}" }]
      end

      def fiber_lines
        ["Fibers", ""] + Introspection.fibers(kernel.state.fetch(:scheduler)).map do |fiber|
          "##{fiber[:pid]} #{fiber[:name]}  #{fiber[:state]}  ticks=#{fiber[:ticks]}  id=#{fiber[:fiber_id]}"
        end
      end

      def driver_lines
        ["Drivers", ""] + Introspection.drivers(kernel.state.fetch(:bus)).flat_map do |driver|
          ["#{driver[:bound] ? '[bound]' : '[open]'} #{driver[:name]}",
           "  #{driver[:driver] || 'no driver'}  #{driver[:resources].join(', ')}"]
        end
      end

      def heap_lines
        @heap.map.with_index(1) { |(name, count), index| "#{index.to_s.rjust(2)}. #{name.ljust(24)} #{count}" }
      end

      def graph_lines
        graph = Introspection.object_graph(kernel.state, depth: 2, limit: 48)
        ["Kernel state object graph", "#{graph[:nodes].length} nodes / #{graph[:edges].length} edges" , ""] +
          graph[:nodes].first(32).map { |node| "#{node[:id]}  #{node[:class]}  #{node[:label]}" }
      end

      def class_lines(type)
        shape = Introspection.class_shape(type)
        [shape[:name], "", "Ancestors", *shape[:ancestors].map { |name| "  #{name}" }, "",
         "Public methods (#{shape[:public_methods].length})",
         *shape[:public_methods].first(32).map { |name| "  #{name}" }, "",
         "Constants (#{shape[:constants].length})",
         *shape[:constants].first(24).map { |name| "  #{name}" }]
      end

      def tick
        @tick_count += 1
        refresh if (@tick_count % 45).zero?
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
