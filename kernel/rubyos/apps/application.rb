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

    class Application
      attr_reader :kernel

      def initialize(kernel: RubyOS::Kernel)
        @kernel = kernel
      end

      def launch(compositor)
        @compositor = compositor
        window = build_window
        window.application = self
        compositor.add_window(window)
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Window", items: [
          GUI::MenuItem.command("Minimize") { compositor.minimize(compositor.focused_window) },
          GUI::MenuItem.command("Close", shortcut: "Ctrl+W") { compositor.close(compositor.focused_window) }
        ])]
      end

      private

      def spacious_desktop?
        @compositor.nil? || @compositor.width >= 600
      end
    end

    class Registry
      include Enumerable

      Entry = Data.define(:name, :application, :description, :category, :dock_label)

      def initialize
        @entries = {}
      end

      def register(name, application, description: "", category: :app, dock_label: nil)
        key = String(name)
        raise ArgumentError, "application already registered: #{key}" if @entries.key?(key)
        validate(application, category)
        @entries[key] = Entry.new(name: key, application:, description: String(description),
                                  category: category.to_sym,
                                  dock_label: String(dock_label || key[0, 5])).freeze
        self
      end

      def replace(name, application)
        key = String(name)
        validate(application, :app)
        previous = @entries[key]
        @entries[key] = if previous
                          Entry.new(name: key, application:,
                                    description: previous.description,
                                    category: previous.category,
                                    dock_label: previous.dock_label).freeze
                        else
                          Entry.new(name: key, application:, description: "Live Ruby application",
                                    category: :app, dock_label: key[0, 5]).freeze
                        end
        self
      end

      def fetch(name)
        @entries.fetch(String(name)).application
      end

      def entry(name)
        @entries.fetch(String(name))
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
