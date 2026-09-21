# frozen_string_literal: true

module RubyOS
  module Apps
    class ShortcutStore
      HEADER = "# RubyOS keybindings v1"
      DEFAULT_PATH = "/home/.rubyos-keybindings"

      attr_reader :vfs, :path

      def initialize(vfs:, path: DEFAULT_PATH)
        @vfs = vfs
        @path = String(path)
      end

      def load
        lines = vfs.read_file(path).lines(chomp: true)
        return [] unless lines.shift == HEADER

        lines.filter_map do |line|
          name, code, mods, extra = line.split("\t", -1)
          next if name.to_s.empty? || code.to_s.empty? || mods.to_s.empty? || extra

          { name: decode(name), code: Integer(code, 10), mods: Integer(mods, 10) }
        rescue ArgumentError
          nil
        end
      rescue FS::NotFound
        []
      end

      def save(bindings)
        rows = Array(bindings).map do |binding|
          [encode(binding.name), Integer(binding.code), Integer(binding.mods)].join("\t")
        end
        vfs.write_file(path, ([HEADER] + rows).join("\n") + "\n")
        rows.length
      end

      def clear
        vfs.unlink(path)
        true
      rescue FS::NotFound
        false
      end

      private

      def encode(value)
        String(value).gsub("%", "%25").gsub("\t", "%09").gsub("\n", "%0A")
      end

      def decode(value)
        String(value).gsub("%0A", "\n").gsub("%09", "\t").gsub("%25", "%")
      end
    end

    class DockStore
      HEADER = "# RubyOS dock v1"
      DEFAULT_PATH = "/home/.rubyos-dock"

      attr_reader :vfs, :path

      def initialize(vfs:, path: DEFAULT_PATH)
        @vfs = vfs
        @path = String(path)
      end

      def load
        lines = vfs.read_file(path).lines(chomp: true)
        return nil unless lines.shift == HEADER

        lines.reject(&:empty?).uniq
      rescue FS::NotFound
        nil
      end

      def save(names)
        values = Array(names).map { |name| String(name) }.reject(&:empty?).uniq
        vfs.write_file(path, ([HEADER] + values).join("\n") + "\n")
        values.length
      end
    end

    class Application
      attr_reader :kernel

      def initialize(kernel: RubyOS::Kernel)
        @kernel = kernel
      end

      # The desktop the window geometry in build_window is written against.
      # A larger desktop scales those numbers up rather than leaving every
      # app marooned at its design size; a smaller one is left alone,
      # because the compact branch of #spacious_desktop? already targets it.
      REFERENCE_WIDTH = 1_024
      REFERENCE_HEIGHT = 768
      # Past this, windows stop growing. A 4K desktop wants more room than a
      # 1080p one, but not four times the font-sized chrome.
      MAXIMUM_SCALE = 2

      def launch(compositor)
        @compositor = compositor
        window = build_window
        window.application = self
        fit_to_desktop(window)
        compositor.add_window(window)
      end

      # Grow +window+ in proportion to how much bigger the desktop is than
      # the reference. Children ride along: #resize_to relayouts them through
      # the same anchors that handle a user drag of the resize grip.
      def fit_to_desktop(window)
        scale = desktop_scale
        return window if scale <= 1

        window.x = (window.x * scale).to_i
        window.y = (window.y * scale).to_i
        window.resize_to((window.width * scale).to_i, (window.height * scale).to_i,
                         maximum_width: @compositor.width - window.x,
                         maximum_height: @compositor.height - @compositor.dock_height - window.y)
      end

      # Whole-number-ish scale for the current desktop, 1 when it is at or
      # below the reference size.
      def desktop_scale
        return 1 if @compositor.nil?

        scale = [@compositor.width.to_f / REFERENCE_WIDTH,
                 @compositor.height.to_f / REFERENCE_HEIGHT].min
        scale.clamp(1, MAXIMUM_SCALE)
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Window", items: [
          GUI::MenuItem.command("Minimize") { compositor.minimize(compositor.focused_window) },
          GUI::MenuItem.command("Close", shortcut: "Ctrl+W") { compositor.close(compositor.focused_window) }
        ])]
      end

      def rebuild_as(application_class)
        application_class.new(kernel:)
      end

      private

      def spacious_desktop?
        @compositor.nil? || @compositor.width >= 600
      end
    end

    class Registry
      include Enumerable

      Entry = Data.define(:name, :application, :description, :category, :dock_label,
                          :source_path, :source_constant)

      def initialize
        @entries = {}
      end

      def register(name, application, description: "", category: :app, dock_label: nil,
                   source_path: nil, source_constant: nil)
        key = String(name)
        raise ArgumentError, "application already registered: #{key}" if @entries.key?(key)
        validate(application, category)
        source_constant ||= application.class.name&.delete_prefix("RubyOS::") if source_path
        @entries[key] = Entry.new(name: key, application:, description: String(description),
                                  category: category.to_sym,
                                  dock_label: String(dock_label || key[0, 5]),
                                  source_path: source_path && String(source_path),
                                  source_constant: source_constant && String(source_constant)).freeze
        self
      end

      def replace(name, application, source_path: nil, source_constant: nil)
        key = String(name)
        validate(application, :app)
        previous = @entries[key]
        @entries[key] = if previous
                          Entry.new(name: key, application:,
                                    description: previous.description,
                                    category: previous.category,
                                    dock_label: previous.dock_label,
                                    source_path: source_path || previous.source_path,
                                    source_constant: source_constant || previous.source_constant).freeze
                        else
                          Entry.new(name: key, application:, description: "Live Ruby application",
                                    category: :app, dock_label: key[0, 5],
                                    source_path: source_path && String(source_path),
                                    source_constant: source_constant && String(source_constant)).freeze
                        end
        self
      end

      def fetch(name)
        @entries.fetch(String(name)).application
      end

      def entry(name)
        @entries.fetch(String(name))
      end

      def entry_for(application)
        @entries.each_value.find { |entry| entry.application.equal?(application) } ||
          raise(KeyError, "application is not registered")
      end

      def entries(category: nil)
        values = @entries.values
        category ? values.select { |entry| entry.category == category.to_sym } : values
      end

      def each
        return enum_for(:each) unless block_given?

        @entries.each_value { |entry| yield entry.name, entry.application }
      end

      private

      def validate(application, category)
        RubyOS.invariant(application.is_a?(Application),
                         "registry accepts RubyOS applications")
        RubyOS.invariant([:app, :demo, :game].include?(category.to_sym),
                         "application category must be app, demo, or game")
      end
    end
  end
end
