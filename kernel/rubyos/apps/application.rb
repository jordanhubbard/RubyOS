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

      def initialize
        @applications = {}
      end

      def register(name, application)
        key = String(name)
        raise ArgumentError, "application already registered: #{key}" if @applications.key?(key)
        @applications[key] = application
        self
      end

      def replace(name, application)
        RubyOS.invariant(application.is_a?(Application),
                         "registry accepts RubyOS applications")
        @applications[String(name)] = application
        self
      end

      def fetch(name)
        @applications.fetch(String(name))
      end

      def each(&block)
        @applications.each(&block)
      end
    end
  end
end
