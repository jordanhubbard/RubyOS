# frozen_string_literal: true

module RubyOS
  module Apps
    class Application
      attr_reader :kernel

      def initialize(kernel: RubyOS::Kernel)
        @kernel = kernel
      end

      def launch(compositor)
        compositor.add_window(build_window)
      end
    end

    class Registry
      include Enumerable

      def initialize
        @applications = {}
      end

      def register(name, application)
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
