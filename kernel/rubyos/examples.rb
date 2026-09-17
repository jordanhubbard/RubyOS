# frozen_string_literal: true

module RubyOS
  # Small, executable language examples live in the kernel image so the same
  # lessons are available from serial, TCP, and the desktop Terminal. They are
  # expressions rather than mini-frameworks: each one demonstrates a Ruby
  # idiom and returns a useful value at the ordinary RubyOS prompt.
  module Examples
    Lesson = Data.define(:name, :summary, :source)

    LESSONS = [
      Lesson.new(
        name: "enumerable_pipeline",
        summary: "lazy Enumerable select/map/take pipeline",
        source: <<~'RUBY'
          (1..Float::INFINITY).lazy
            .select(&:odd?)
            .map { |number| number * number }
            .first(5)
        RUBY
      ),
      Lesson.new(
        name: "pattern_matching",
        summary: "destructure a kernel event with case/in",
        source: <<~'RUBY'
          event = { kind: :device, payload: { name: "virtio-net", bound: true } }
          case event
          in kind: :device, payload: { name:, bound: true }
            "#{name} is ready"
          else
            "not ready"
          end
        RUBY
      ),
      Lesson.new(
        name: "fiber_stream",
        summary: "resume a stateful Fiber producer",
        source: <<~'RUBY'
          producer = Fiber.new do
            value = 1
            loop do
              Fiber.yield(value)
              value *= 2
            end
          end
          6.times.map { producer.resume }
        RUBY
      ),
      Lesson.new(
        name: "mixin_protocol",
        summary: "compose behavior with a module and super",
        source: <<~'RUBY'
          trace = Module.new do
            def call(value) = [self.class.name || "anonymous", super]
          end
          worker = Class.new do
            prepend trace
            def call(value) = value * 2
          end
          worker.new.call(21)
        RUBY
      ),
      Lesson.new(
        name: "method_objects",
        summary: "pass bound methods as first-class callables",
        source: <<~'RUBY'
          formatter = "rubyos".method(:upcase)
          [formatter.call, formatter.owner, formatter.name]
        RUBY
      ),
      Lesson.new(
        name: "data_records",
        summary: "immutable value semantics with Data",
        source: <<~'RUBY'
          Point = Data.define(:x, :y) unless defined?(Point)
          points = [Point.new(x: 3, y: 4), Point.new(x: 6, y: 8)]
          points.map { |point| Math.sqrt(point.x**2 + point.y**2) }
        RUBY
      )
    ].each(&:freeze).freeze

    module_function

    def each(&block) = LESSONS.each(&block)

    def fetch(name)
      LESSONS.find { |lesson| lesson.name == String(name) } ||
        raise(KeyError, "unknown example: #{name}")
    end

    def run(name, context: TOPLEVEL_BINDING)
      lesson = fetch(name)
      eval(lesson.source, context, "/examples/#{lesson.name}.rb", 1)
    end

    def files
      LESSONS.to_h { |lesson| ["#{lesson.name}.rb", lesson.source] }
    end
  end
end
