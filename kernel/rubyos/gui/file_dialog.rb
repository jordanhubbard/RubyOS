# frozen_string_literal: true

module RubyOS
  module GUI
    class FileDialog
      MODES = [:open, :save].freeze

      attr_reader :compositor, :vfs, :mode, :cwd, :result, :window

      def initialize(compositor:, vfs:, mode: :open, path: nil,
                     title: nil, default_name: "untitled.rb", extensions: nil,
                     on_accept: nil, on_cancel: nil)
        @compositor = compositor
        @vfs = vfs
        @mode = mode.to_sym
        raise ArgumentError, "file dialog mode must be :open or :save" unless MODES.include?(@mode)

        @cwd, filename = split_path(path, default_name)
        @extensions = Array(extensions).map { |extension| String(extension).downcase }.freeze
        @on_accept = on_accept
        @on_cancel = on_cancel
        @done = false
        build(title || (mode == :save ? "Save File" : "Open File"), filename)
        refresh
        compositor.add_window(window)
      end

      def done? = @done
      def filename = @filename&.text

      def filename=(value)
        raise RubyOS::Error, "open dialogs do not have a filename field" unless @filename

        @filename.replace(String(value))
      end

      def navigate(destination)
        vfs.readdir(destination)
        @cwd = normalize(destination)
        refresh
        true
      rescue FS::Error => error
        report(error.message, error: true)
        false
      end

      def go_up(*)
        return false if cwd == "/"

        parts = cwd.split("/").reject(&:empty?)
        parts.pop
        navigate("/" + parts.join("/"))
      end

      def activate(item)
        return navigate(item.fetch(:path)) if item.fetch(:kind) == :directory

        if mode == :save
          @filename.replace(item.fetch(:label))
          report("Press Save to replace #{item.fetch(:label)}")
          true
        else
          accept(item.fetch(:path))
        end
      end

      def accept(path = nil, *)
        candidate = path || (mode == :open ? @list.selected_item&.fetch(:path) : save_path)
        if mode == :open && !candidate
          report("Select a file to open", error: true)
          return false
        end
        return false unless candidate

        if mode == :open && vfs.stat(candidate).type == :directory
          return navigate(candidate)
        end
        @result = candidate
        finish
        @on_accept&.call(candidate)
        true
      rescue FS::Error => error
        report(error.message, error: true)
        false
      end

      def cancel(*)
        return false if done?

        finish
        @on_cancel&.call
        true
      end

      private

      def build(title, filename)
        spacious = compositor.width >= 600
        width, height = spacious ? [500, 330] : [420, 216]
        x = [(compositor.width - width) / 2, 8].max
        y = [(compositor.height - height) / 2, Compositor::MENU_HEIGHT + 6].max
        content_width = width - 36
        list_height = height - (mode == :save ? 142 : 112)
        @window = Window.new(title, x:, y:, width:, height:, background: 0x151c29)
        @path_label = window.add(Label.new(cwd, x: 8, y: 5,
                                           width: content_width - 118, color: 0xffffff))
        window.add(Button.new("Up", x: content_width - 104, y: 0, width: 48, height: 24,
                              action: method(:go_up)))
        window.add(Button.new("Home", x: content_width - 50, y: 0, width: 56, height: 24,
                              action: ->(*) { navigate("/home") }))
        @list = window.add(ListView.new(x: 8, y: 34, width: content_width,
                                        height: list_height, background: 0x1d2535,
                                        on_activate: method(:activate),
                                        on_back: method(:go_up), on_cancel: method(:cancel)))
        controls_y = 44 + list_height
        if mode == :save
          window.add(Label.new("Name", x: 8, y: controls_y + 5, width: 40, color: 0xffd866))
          @filename = window.add(TextInput.new(text: filename, x: 52, y: controls_y,
                                               width: content_width - 52, height: 26,
                                               background: 0x211a29,
                                               on_submit: ->(*) { accept }))
          controls_y += 34
        end
        @status = window.add(Label.new("", x: 8, y: controls_y + 5,
                                       width: content_width - 150, color: 0xa8d8ff))
        action_label = mode == :save ? "Save" : "Open"
        window.add(Button.new(action_label, x: content_width - 138, y: controls_y,
                              width: 62, height: 26, action: ->(*) { accept }))
        window.add(Button.new("Cancel", x: content_width - 70, y: controls_y,
                              width: 70, height: 26, action: method(:cancel)))
        window.focus_child(@list)
      end

      def refresh
        items = vfs.readdir(cwd).reject { |entry| [".", ".."].include?(entry) }.sort.filter_map do |entry|
          path = join(cwd, entry)
          kind = vfs.stat(path).type
          next if kind == :file && !extension_allowed?(entry)

          { label: entry, path:, kind: }
        end
        @path_label.text = cwd
        @list.replace(items)
        report("#{items.length} item#{items.length == 1 ? '' : 's'} | arrows + Enter")
        window.invalidate
      end

      def save_path
        name = @filename.text.strip
        if name.empty? || name.include?("/")
          report("Enter a filename without /", error: true)
          return nil
        end
        join(cwd, name)
      end

      def finish
        @done = true
        compositor.close(window)
      end

      def report(message, error: false)
        @status.text = String(message)
        @status.color = error ? 0xff668a : 0xa8d8ff
        @status.invalidate
      end

      def extension_allowed?(name)
        @extensions.empty? || @extensions.any? { |extension| name.downcase.end_with?(extension) }
      end

      def split_path(path, default_name)
        value = String(path || "").strip
        return ["/home", String(default_name)] if value.empty?
        return [normalize(value), String(default_name)] if value.end_with?("/")

        parts = value.split("/").reject(&:empty?)
        name = parts.pop || default_name
        ["/" + parts.join("/"), name]
      end

      def normalize(path)
        parts = []
        String(path).split("/").each do |part|
          next if part.empty? || part == "."
          part == ".." ? parts.pop : parts << part
        end
        "/" + parts.join("/")
      end

      def join(directory, name)
        directory == "/" ? "/#{name}" : "#{directory}/#{name}"
      end
    end
  end
end
