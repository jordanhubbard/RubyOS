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
      attr_reader :path, :list, :status, :export_button

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
        drag_options = if transfer&.export_supported?
                         { on_drag: method(:begin_export_drag),
                           on_drop: method(:finish_export_drag) }
                       else
                         {}
                       end
        @list = @window.add(GUI::ListView.new(x: 8, y: 34, width: content_width,
                                              height: list_height,
                                              background: 0x1d2535,
                                              on_activate: method(:activate_entry),
                                              on_back: method(:go_up), **drag_options),
                            anchors: [:left, :right, :top, :bottom],
                            minimum_width: 80, minimum_height: 30)
        @status = @window.add(GUI::Label.new("", x: 8, y: 44 + list_height,
                                             width: content_width - (transfer&.export_supported? ? 78 : 0),
                                             height: 22, color: 0xa8d8ff),
                              anchors: [:left, :right, :bottom], minimum_width: 80)
        if transfer&.export_supported?
          @export_button = @window.add(
            GUI::Button.new("Export", x: content_width - 70, y: 44 + list_height,
                            width: 70, height: 24, action: method(:export_selected)),
            anchors: [:right, :bottom]
          )
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
        if ImageViewer.image_path?(item.fetch(:path))
          ImageViewer.new(path: item.fetch(:path)).launch(@compositor)
        else
          Editor.new(path: item.fetch(:path)).launch(@compositor)
        end
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

        export_item(@list.selected_item)
      end

      def begin_export_drag(item)
        if item.fetch(:kind) == :file
          show_transfer_status("Drop #{item.fetch(:label)} on Export")
        else
          show_transfer_status("Only files can be exported", error: true)
        end
        true
      end

      def finish_export_drag(item, point_x, point_y)
        unless export_button&.contains?(point_x, point_y)
          show_transfer_status("Drag a file onto Export", error: true)
          return false
        end
        export_item(item)
      end

      def export_item(item)
        return false unless transfer&.export_supported?

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

    class TerminalHistory
      HEADER = "# RubyOS terminal history v1"
      DEFAULT_PATH = "/home/.rubyos-history"

      def initialize(vfs:, path: DEFAULT_PATH, limit: 100)
        @vfs = vfs
        @path = String(path)
        @limit = Integer(limit)
      end

      def load
        lines = @vfs.read_file(@path).lines(chomp: true)
        return [] unless lines.shift == HEADER

        lines.last(@limit).filter_map do |line|
          next if line.empty?
          line.gsub("%0A", "\n").gsub("%25", "%")
        end
      rescue FS::NotFound
        []
      end

      def save(commands)
        rows = Array(commands).last(@limit).map do |command|
          String(command).gsub("%", "%25").gsub("\n", "%0A")
        end
        @vfs.write_file(@path, ([HEADER] + rows).join("\n") + "\n")
        rows.length
      end
    end

    class Terminal < Application
      MAX_SCROLLBACK = 500
      MAX_HISTORY = 100

      attr_reader :last_result, :history, :transcript_view, :completion_candidates

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
        @shell = Shell.new(output: @output, desktop: method(:launch_desktop))
        @pending_source = +""
        @transcript = ["RubyOS console", "Commands and Ruby expressions share this prompt. Type help to begin."]
        @history_store ||= TerminalHistory.new(vfs: kernel.state.fetch(:vfs), limit: MAX_HISTORY)
        @history ||= @history_store.load
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
          @prompt_label = window.add(GUI::Label.new("rubyos>", x: 8, y: prompt_y, width: 64,
                                                    color: 0xffd866), anchors: [:left, :bottom])
          @input = window.add(GUI::TextInput.new(x: 72, y: prompt_y - 6,
                                                 width: window_width - 100, height: 28,
                                                 background: 0x211a29,
                                                 on_submit: method(:evaluate),
                                                 on_history: method(:navigate_history),
                                                 on_complete: method(:complete_input)),
                              anchors: [:left, :right, :bottom], minimum_width: 56)
          window.focus_child(@input)
        end
      end

      def evaluate(source)
        source = String(source).strip
        return nil if source.empty?

        combined = @pending_source.empty? ? source : "#{@pending_source}\n#{source}"
        unless @shell.source_complete?(combined)
          prompt = @pending_source.empty? ? "rubyos>" : "....>"
          @transcript << "#{prompt} #{source}"
          @pending_source = combined
          @prompt_label.text = "....>"
          @transcript_view.replace(@transcript.join("\n"), scroll: :end)
          @input.replace("")
          return :continue
        end
        @pending_source.clear
        @prompt_label.text = "rubyos>"

        @output.clear
        @shell.execute_line(combined)
        @last_result = @output.string.sub(/\n\z/, "")
        @history << combined unless @history.last == combined
        @history = @history.last(MAX_HISTORY)
        @history_store.save(@history)
        @history_index = @history.length
        @transcript << "rubyos> #{combined.gsub("\n", "\n....> ")}"
        @transcript.concat(@last_result.split("\n")) unless @last_result.empty?
        @transcript = @transcript.last(MAX_SCROLLBACK)
        @transcript_view.replace(@transcript.join("\n"), scroll: :end)
        @input.replace("")
        @last_result
      end

      def complete_input(source)
        completed, @completion_candidates = @shell.complete(source)
        if @completion_candidates.length > 1 && completed == source
          @transcript << @completion_candidates.first(12).join("  ")
          @transcript_view.replace(@transcript.last(MAX_SCROLLBACK).join("\n"), scroll: :end)
        end
        completed
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

      def launch_desktop(name, *arguments)
        if name.casecmp?("Editor")
          path = arguments.first || "/home/welcome.txt"
          return Editor.new(kernel:, path:).launch(@compositor)
        end

        registry = Catalog.build(kernel:)
        entry = registry.entries.find { |candidate| candidate.name.casecmp?(name) }
        raise KeyError, "unknown desktop application: #{name}" unless entry

        entry.application.launch(@compositor)
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

      def rebuild_as(application_class)
        application_class.new(kernel:, store:)
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
        key = if code.between?(Input::KEY_F1, Input::KEY_F5)
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
      attr_reader :path, :content, :reload_error, :file_dialog, :input, :dirty

      def initialize(path: "/home/welcome.txt", runtime: nil,
                     application_name: nil, initial_content: nil,
                     target_window: nil, title_prefix: "Editor",
                     source_mode: false, **)
        super(**)
        @path = path
        @runtime = runtime
        @application_name = application_name
        @target_window = target_window
        @title_prefix = String(title_prefix)
        @source_mode = source_mode
        @content = kernel.state.fetch(:vfs).read_file(path)
      rescue FS::NotFound
        @content = String(initial_content || "")
      ensure
        @saved_content = @content.to_s.dup
        @dirty = false
      end

      def save(text = nil)
        @content = String(text || @input&.text || content)
        kernel.state.fetch(:vfs).write_file(path, @content)
        @saved_content = @content.dup
        @dirty = false
        refresh_title
        show_status("Saved #{path}") if @status
        self
      end

      def cancel_changes(*)
        @content = @saved_content.dup
        @input&.replace(@content, notify: false)&.move_cursor(0)
        @dirty = false
        refresh_title
        show_status("Changes cancelled") if @status
        self
      end

      def load_path(new_path)
        contents = kernel.state.fetch(:vfs).read_file(new_path)
        @path = String(new_path)
        @content = contents
        @saved_content = contents.dup
        @dirty = false
        @input&.replace(contents, notify: false)&.move_cursor(0)
        refresh_title
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
        self
      end

      def reload(*)
        raise RubyOS::Error, "editor is not attached to a live application" unless @runtime
        previous = @runtime.registry.fetch(@application_name)
        save
        @runtime.reload(@application_name, path:)
        replacement = @runtime.registry.fetch(@application_name)
        @compositor.replace_application(@application_name, previous, replacement)
        @compositor.close(@target_window) if @target_window &&
                                              @compositor.windows.include?(@target_window)
        replacement.launch(@compositor)
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
        @window = GUI::Window.new("#{@title_prefix} - #{path}", x: 72, y: 54,
                                  width: 350, height: 184,
                                  background: 0x171a24).tap do |window|
          @input = window.add(GUI::EditorInput.new(text: content, x: 0, y: 0,
                                                    width: 326, height: 108,
                                                    background: 0x11151e,
                                                    on_change: method(:buffer_changed),
                                                    on_save: method(:save),
                                                    on_quit: -> { @compositor.close(@window) },
                                                    on_command: method(:editor_command)),
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
            @status = window.add(GUI::Label.new("L1 C1  Saved", x: 0, y: 116,
                                                width: 326, color: 0xa8d8ff),
                                 anchors: [:left, :right, :bottom], minimum_width: 80)
          end
        end
      end

      def menus(compositor)
        items = []
        items << GUI::MenuItem.command("Open...") { open_dialog } unless @source_mode
        items << GUI::MenuItem.command("Save", shortcut: "Ctrl+S") { save }
        items << GUI::MenuItem.command("Save As...") { save_as_dialog } unless @source_mode
        items << GUI::MenuItem.separator
        items << GUI::MenuItem.command("Cancel Changes") { cancel_changes }
        items << GUI::MenuItem.command("Reload Ruby") { reload } if @runtime
        edit_items = [
          GUI::MenuItem.command("Cut") { @input.cut },
          GUI::MenuItem.command("Copy", shortcut: "Ctrl+C") { @input.copy },
          GUI::MenuItem.command("Paste") { @input.paste },
          GUI::MenuItem.separator,
          GUI::MenuItem.command("Select All") { @input.select_all }
        ]
        navigation_items = [
          GUI::MenuItem.command("Beginning of Line", shortcut: "Ctrl+A") do
            @input.move_line_edge(:start)
            refresh_editor_status
          end,
          GUI::MenuItem.command("End of Line", shortcut: "Ctrl+E") do
            @input.move_line_edge(:end)
            refresh_editor_status
          end,
          GUI::MenuItem.command("Backward / Forward Word", shortcut: "Alt+B / Alt+F", enabled: false),
          GUI::MenuItem.command("Backward / Forward Sentence", shortcut: "Alt+A / Alt+E", enabled: false),
          GUI::MenuItem.command("Previous / Next Paragraph", shortcut: "Alt+{ / Alt+}", enabled: false),
          GUI::MenuItem.command("Previous / Next Page", shortcut: "Alt+V / Ctrl+V", enabled: false),
          GUI::MenuItem.command("Buffer Start / End", shortcut: "Alt+< / Alt+>", enabled: false),
          GUI::MenuItem.command("Recenter", shortcut: "Ctrl+L") do
            @input.recenter
            show_status("Recenter")
          end
        ]
        [GUI::Menu.new(title: "File", items:),
         GUI::Menu.new(title: "Edit", items: edit_items),
         GUI::Menu.new(title: "Navigate", items: navigation_items), *super]
      end

      def rebuild_as(application_class)
        application_class.new(
          kernel:, path:, runtime: @runtime, application_name: @application_name,
          initial_content: @saved_content, target_window: @target_window,
          title_prefix: @title_prefix, source_mode: @source_mode
        )
      end

      private

      def buffer_changed(text)
        @content = String(text)
        @dirty = @content != @saved_content
        refresh_title
        refresh_editor_status
      end

      def editor_command(message)
        if message
          show_status(message)
        else
          refresh_editor_status
        end
      end

      def refresh_editor_status
        return unless @status && @input

        state = dirty ? "Unsaved" : "Saved"
        show_status("L#{@input.caret_line + 1} C#{@input.caret_column + 1}  #{state}")
      end

      def refresh_title
        @window.title = "#{@title_prefix} - #{path}#{dirty ? ' *' : ''}" if @window
      end

      def show_status(message, error: false)
        @status.text = String(message)[0, 52]
        @status.color = error ? 0xff668a : 0xc3e88d
        @status.invalidate
      end
    end

    class SourceWorkspace
      attr_reader :runtime, :registry, :compositor, :last_editor

      def initialize(runtime:, registry:, compositor:)
        @runtime = runtime
        @registry = registry
        @compositor = compositor
      end

      def open(window = compositor.focused_window)
        raise RubyOS::Error, "focus an application window first" unless window&.application

        entry = registry.entry_for(window.application)
        raise RubyOS::Error, "source is unavailable for #{entry.name}" unless entry.source_path

        @last_editor = Editor.new(
          kernel: entry.application.kernel,
          path: runtime.overlay_path(entry.name),
          initial_content: runtime.source_for(entry.name),
          runtime:, application_name: entry.name, target_window: window,
          title_prefix: "Source", source_mode: true
        )
        last_editor.launch(compositor)
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

    class ImageCanvas < GUI::View
      attr_reader :source, :pan_x, :pan_y

      def initialize(on_change: nil, **options)
        super(**options)
        @source = nil
        @pan_x = @pan_y = 0
        @on_change = on_change
      end

      def source=(value)
        @source = value
        center
        invalidate
      end

      def center(*)
        @pan_x = [((source&.width || width) - width) / 2, 0].max
        @pan_y = [((source&.height || height) - height) / 2, 0].max
        changed
        true
      end

      def draw(surface)
        super
        return unless source

        offset_x = source.width < width ? (width - source.width) / 2 : -pan_x
        offset_y = source.height < height ? (height - source.height) / 2 : -pan_y
        surface.draw_surface(x + offset_x, y + offset_y, source)
      end

      def handle(event)
        return false unless focused && event.respond_to?(:fetch)

        if event.fetch("kind", 0) == Input::POINTER_WHEEL
          delta = event.fetch("dy", 0)
          return pan(0, delta.positive? ? -16 : 16)
        end
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN

        case event.fetch("code", 0)
        when GUI::TextInput::LEFT_KEY then pan(-16, 0)
        when GUI::TextInput::RIGHT_KEY then pan(16, 0)
        when GUI::TextInput::UP_KEY then pan(0, -16)
        when GUI::TextInput::DOWN_KEY then pan(0, 16)
        when GUI::TextInput::HOME_KEY then center
        else false
        end
      end

      def focusable? = true

      private

      def pan(dx, dy)
        return false unless source

        previous = [pan_x, pan_y]
        @pan_x = [[pan_x + dx, 0].max, [source.width - width, 0].max].min
        @pan_y = [[pan_y + dy, 0].max, [source.height - height, 0].max].min
        changed if previous != [pan_x, pan_y]
        previous != [pan_x, pan_y]
      end

      def changed
        @on_change&.call(self)
        invalidate
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
      EXTENSIONS = %w[.bmp .png .jpg .jpeg .ppm].freeze
      MAX_BYTES = 16 * 1024 * 1024

      attr_reader :path, :surface, :file_dialog, :canvas, :last_error

      def self.image_path?(path)
        EXTENSIONS.include?(File.extname(String(path)).downcase)
      end

      def self.decode_ppm(bytes)
        bytes = String(bytes).b
        offset = 0
        token = lambda do
          loop do
            offset += 1 while offset < bytes.bytesize && bytes.getbyte(offset).chr.match?(/\s/)
            if bytes.getbyte(offset) == 35
              offset += 1 until offset >= bytes.bytesize || bytes.getbyte(offset) == 10
            else
              break
            end
          end
          start = offset
          offset += 1 while offset < bytes.bytesize && !bytes.getbyte(offset).chr.match?(/\s/)
          raise ArgumentError, "truncated PPM header" if start == offset
          bytes.byteslice(start...offset)
        end

        magic = token.call
        raise ArgumentError, "expected P3 or P6 portable pixmap" unless %w[P3 P6].include?(magic)
        width = Integer(token.call, 10)
        height = Integer(token.call, 10)
        maximum = Integer(token.call, 10)
        raise ArgumentError, "invalid PPM dimensions" unless width.positive? && height.positive?
        raise ArgumentError, "PPM is too large" if width * height * 4 > MAX_BYTES
        raise ArgumentError, "invalid PPM sample maximum" unless (1..65_535).cover?(maximum)

        samples = if magic == "P3"
                    Array.new(width * height * 3) { Integer(token.call, 10) }
                  else
                    if bytes.getbyte(offset) == 13 && bytes.getbyte(offset + 1) == 10
                      offset += 2
                    elsif offset < bytes.bytesize && bytes.getbyte(offset).chr.match?(/\s/)
                      offset += 1
                    end
                    sample_bytes = maximum < 256 ? 1 : 2
                    payload = bytes.byteslice(offset, width * height * 3 * sample_bytes)
                    raise ArgumentError, "truncated PPM pixels" unless payload&.bytesize == width * height * 3 * sample_bytes
                    sample_bytes == 1 ? payload.bytes : payload.unpack("n*")
                  end
        raise ArgumentError, "PPM sample exceeds maximum" if samples.any? { |sample| sample.negative? || sample > maximum }

        bitmap = Media::Bitmap.new(width, height)
        samples.each_slice(3).with_index do |(red, green, blue), index|
          scale = ->(sample) { (sample * 255 + maximum / 2) / maximum }
          bitmap.put(index % width, index / width,
                     (scale.call(red) << 16) | (scale.call(green) << 8) | scale.call(blue))
        end
        bitmap
      end

      def initialize(path: nil, surface_loader: nil, **options)
        super(**options)
        @path = path
        @surface_loader = surface_loader
      end

      def build_window
        @window = GUI::Window.new("Image Viewer", x: 42, y: 32, width: 396, height: 232,
                                  minimum_width: 280, minimum_height: 180,
                                  background: 0x10151f).tap do |window|
          @canvas = window.add(ImageCanvas.new(
            x: 4, y: 4, width: 352, height: 150, background: 0x080b12,
            on_change: method(:update_status)
          ), anchors: [:left, :right, :top, :bottom],
             minimum_width: 180, minimum_height: 80)
          @status = window.add(GUI::Label.new("Open a BMP, PNG, JPEG, or PPM from the Ruby VFS",
                                               x: 4, y: 164, width: 260,
                                               height: 24, background: 0x151c29,
                                               color: 0xa8d8ff),
                               anchors: [:left, :right, :bottom], minimum_width: 100)
          window.add(GUI::Button.new("Open...", x: 276, y: 158, width: 80, height: 26,
                                     action: method(:open_dialog)), anchors: [:right, :bottom])
          window.focus_child(@canvas)
          window.on_close { release_surface }
        end
        load_path(path) if path
        @window
      end

      def open_dialog(*)
        @file_dialog = GUI::FileDialog.new(
          compositor: @compositor, vfs: kernel.state.fetch(:vfs), mode: :open,
          path: path || "/home", title: "Open Image", extensions: EXTENSIONS,
          on_accept: method(:load_path)
        )
      end

      def load_path(new_path)
        raise RubyOS::Error, "image decoding requires the RemoteOS desktop" unless image_client || @surface_loader

        stat = kernel.state.fetch(:vfs).stat(new_path)
        raise FS::IsDirectory, new_path unless stat.type == :file
        raise RubyOS::Error, "image exceeds #{MAX_BYTES} byte limit" if stat.size > MAX_BYTES

        bytes = kernel.state.fetch(:vfs).read_file(new_path)
        loaded = if @surface_loader
                   @surface_loader.call(bytes)
                 elsif File.extname(String(new_path)).downcase == ".ppm"
                   bitmap = self.class.decode_ppm(bytes)
                   Bridge::Surface.create(image_client, width: bitmap.width, height: bitmap.height)
                                  .upload(bitmap.bytes)
                 else
                   Bridge::Surface.load_image(image_client, bytes)
                 end
        release_surface
        @surface = loaded
        @path = String(new_path)
        @canvas.source = loaded
        @window.title = "Image - #{File.basename(path)}"
        @last_error = nil
        update_status
        true
      rescue StandardError => error
        @last_error = error
        @status.text = "#{error.class}: #{error.message}"[0, 50] if @status
        @status.color = 0xff668a if @status
        @status&.invalidate
        false
      end

      def center(*)
        canvas.center
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Image", items: [
          GUI::MenuItem.command("Open...") { open_dialog },
          GUI::MenuItem.command("Center", shortcut: "Home", enabled: !surface.nil?) { center }
        ]), *super]
      end

      private

      def image_client = @compositor&.file_transfer&.client

      def release_surface
        @surface&.destroy
        @surface = nil
        @canvas.source = nil if @canvas
        true
      end

      def update_status(*)
        return unless @status

        if surface
          @status.text = "#{surface.width}x#{surface.height}  |  pan #{canvas.pan_x},#{canvas.pan_y}"
          @status.color = 0xc3e88d
        end
        @status.invalidate
      end
    end

    class CanvasPreview < GUI::View
      attr_reader :bitmap

      def initialize(bitmap, scale: 5, on_key: nil, **options)
        super(**options)
        @bitmap = bitmap
        @scale = scale
        @on_key = on_key
      end

      def bitmap=(value)
        @bitmap = value
        invalidate
        value
      end

      def draw(surface)
        surface.fill_rect(x - 2, y - 2, bitmap.width * @scale + 4,
                          bitmap.height * @scale + 4, 0x604481)
        pixels = @bitmap.raster
        @bitmap.height.times do |row|
          @bitmap.width.times do |column|
            surface.fill_rect(x + column * @scale, y + row * @scale,
                              @scale, @scale, pixels[row * @bitmap.width + column])
          end
        end
      end

      def handle(event)
        return false unless focused && @on_key && event.respond_to?(:fetch)
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN

        !!@on_key.call(event)
      end

      def focusable? = !@on_key.nil?
    end

    class MediaWorkbench < Application
      WIDTH = 60
      HEIGHT = 22
      FRAME_SECONDS = 1.0 / 30

      attr_reader :program, :playing, :direction, :transition, :preview,
                  :status, :meter, :cue_count

      def initialize(**options)
        super
        @program = :a
        @playing = false
        @direction = :left_to_right
        @cue_count = 0
      end

      def build_program_a
        bitmap = Media::Bitmap.new(WIDTH, HEIGHT)
        colors = [0xff668a, 0xffce73, 0xc3e88d, 0x51d6c5,
                  0x68aaff, 0x8f7cff, 0xb396ff, 0x34243f]
        band = (WIDTH.to_f / colors.length).ceil
        colors.each_with_index do |color, index|
          bitmap.rect(index * band, 0, [band, WIDTH - index * band].min, HEIGHT,
                      color:)
        end
        # A small faceted Ruby mark makes this more than a generic test card.
        bitmap.rect(24, 5, 12, 12, color: 0x180c24)
        bitmap.line(30, 6, 25, 11, color: 0xffffff)
        bitmap.line(30, 6, 35, 11, color: 0xffffff)
        bitmap.line(25, 11, 30, 16, color: 0xff668a)
        bitmap.line(35, 11, 30, 16, color: 0xff668a)
        bitmap.line(25, 11, 35, 11, color: 0xffd9e3)
        bitmap
      end

      def build_program_b
        Media::Bitmap.new(WIDTH, HEIGHT).tap do |bitmap|
          HEIGHT.times do |y|
            WIDTH.times.each_slice(2) do |columns|
              columns.each do |x|
                red = (x * 7 + y * 3) & 0xff
                green = (y * 11 + (x / 3) * 5) & 0xff
                blue = ((x + y) * 9) & 0xff
                bitmap.put(x, y, red << 16 | green << 8 | blue)
              end
            end
          end
          6.times do |index|
            inset = index * 2
            bitmap.line(inset, inset, WIDTH - 1 - inset, inset, color: 0xffffff)
            bitmap.line(WIDTH - 1 - inset, inset, WIDTH - 1 - inset,
                        HEIGHT - 1 - inset, color: 0x51d6c5)
          end
        end
      end

      def build_window
        @program_a = build_program_a
        @program_b = build_program_b
        @timeline = Media::Timeline.new
        @window = GUI::Window.new("Ruby Media Studio", x: 70, y: 14,
                                  width: 340, height: 238,
                                  minimum_width: 340, minimum_height: 238,
                                  resizable: false,
                                  background: 0x0c0912).tap do |window|
          @preview = window.add(CanvasPreview.new(@program_a, scale: 5,
                                                   on_key: method(:handle_key),
                                                   x: 10, y: 4, width: 300, height: 110))
          @status = window.add(GUI::Label.new("", x: 2, y: 120, width: 316,
                                               height: 20, color: 0xe8dff5))
          @meter = window.add(GUI::Meter.new(value: 0, maximum: 100,
                                              label: "A  0%  B", x: 2, y: 142,
                                              width: 306, height: 22,
                                              color: 0x51d6c5))
          window.add(GUI::Button.new("A CUT", x: 2, y: 170, width: 72, height: 24,
                                     action: method(:select_a)))
          window.add(GUI::Button.new("WIPE", x: 80, y: 170, width: 72, height: 24,
                                     action: method(:start_wipe)))
          window.add(GUI::Button.new("B CUT", x: 158, y: 170, width: 72, height: 24,
                                     action: method(:select_b)))
          window.add(GUI::Button.new("DIR", x: 236, y: 170, width: 72, height: 24,
                                     action: method(:cycle_direction)))
          window.on_tick { tick }
          refresh_status
        end
      end

      def select_a(*) = select_program(:a)
      def select_b(*) = select_program(:b)

      def select_program(value)
        value = value.to_sym
        raise ArgumentError, "unknown program" unless %i[a b].include?(value)

        @program = value
        @playing = false
        @transition = nil
        @timeline.clear.seek(0)
        @preview.bitmap = program == :a ? @program_a : @program_b
        refresh_status
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Studio", items: [
          GUI::MenuItem.command("Cut to Program A", shortcut: "1") { select_a },
          GUI::MenuItem.command("Run wipe", shortcut: "W / Space") { start_wipe },
          GUI::MenuItem.command("Cut to Program B", shortcut: "2") { select_b },
          GUI::MenuItem.command("Next direction", shortcut: "D") { cycle_direction }
        ]), *super]
      end

      def start_wipe(*)
        source, destination, target = if program == :a
                                        [@program_a, @program_b, :b]
                                      else
                                        [@program_b, @program_a, :a]
                                      end
        @transition = Media::WipeTransition.new(source:, destination:, direction:)
        @target_program = target
        @timeline.clear.seek(0)
        @timeline.animate(transition, :progress, from: 0, to: 1,
                          duration: 1, easing: :smooth)
        @preview.bitmap = transition.output
        @playing = true
        play_stinger
        refresh_status
        true
      end

      def cycle_direction(*)
        index = Media::WipeTransition::DIRECTIONS.index(direction)
        @direction = Media::WipeTransition::DIRECTIONS.fetch(
          (index + 1) % Media::WipeTransition::DIRECTIONS.length
        )
        @transition.direction = direction if playing
        refresh_status
        true
      end

      def tick
        return false unless playing

        @timeline.advance(FRAME_SECONDS)
        @preview.invalidate
        if transition.complete?
          @program = @target_program
          @playing = false
          @preview.bitmap = program == :a ? @program_a : @program_b
        end
        refresh_status
        true
      end

      def handle_key(event)
        case event.fetch("code", 0)
        when 49 then select_a
        when 50 then select_b
        when 119, 87, 32 then start_wipe
        when 100, 68 then cycle_direction
        else false
        end
      end

      private

      def refresh_status
        progress = transition ? (transition.progress * 100).round : (program == :a ? 0 : 100)
        label = direction.to_s.tr("_", " ")
        @status.text = "#{playing ? 'ON AIR' : 'READY'}  Program #{program.upcase}  |  #{label}"
        @status.color = playing ? 0xffce73 : 0xe8dff5
        @meter.value = progress
        @meter.label = "A  #{progress.to_s.rjust(3)}%  B"
        @window&.invalidate
        true
      end

      def play_stinger
        client = @compositor&.file_transfer&.client
        output = @compositor&.audio_output
        return false unless output || client&.features&.include?("audio.pcm")

        owned_output = !output
        output ||= Sound::BridgeOutput.new(client)
        high = Sound::Waveform.square(880, duration_ms: 45, amplitude: 0.12)
        low = Sound::Waveform.sine(440, duration_ms: 90, amplitude: 0.10)
        output.play(Sound::Mixer.new.mix(high, low))
        @cue_count += 1
        true
      ensure
        output&.close if owned_output
      end
    end
  end
end
