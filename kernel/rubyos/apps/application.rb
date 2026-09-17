# frozen_string_literal: true

module RubyOS
  module Apps
    class Application
      attr_reader :kernel

      def initialize(kernel: RubyOS::Kernel)
        @kernel = kernel
      end

      def launch(compositor)
        @compositor = compositor
        compositor.add_window(build_window)
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
