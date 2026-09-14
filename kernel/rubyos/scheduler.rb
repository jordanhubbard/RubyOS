# frozen_string_literal: true

module RubyOS
  # Cooperative kernel scheduler. A timer interrupt will eventually call
  # #tick; the hosted exploration drives it directly. Fibers make suspension
  # and resumption explicit and keep the design idiomatic Ruby.
  class Scheduler
    Task = Struct.new(:name, :fiber, :state, :result, :failure, :wake_at,
                      keyword_init: true)

    attr_reader :ticks

    def initialize(monotonic_ms: nil, sleeper: nil)
      @run_queue = []
      @sleeping = []
      @tasks = []
      @ticks = 0
      @current = nil
      @monotonic_ms = monotonic_ms || method(:platform_monotonic_ms)
      @sleeper = sleeper || method(:platform_sleep)
    end

    def spawn(name, &body)
      raise ArgumentError, "task body required" unless body

      task = nil
      fiber = Fiber.new do
        begin
          task.state = :running
          task.result = body.call
          task.state = :complete
        rescue Exception => error # Kernel boundary records every task failure.
          task.failure = error
          task.state = :failed
        end
      end
      task = Task.new(name:, fiber:, state: :ready, result: nil, failure: nil, wake_at: nil)
      @tasks << task
      @run_queue << task
      task
    end

    def tick
      @ticks += 1
      wake_sleepers
      task = @run_queue.shift
      return false unless task

      @current = task
      task.state = :running
      task.fiber.resume if task.fiber.alive?
      if task.fiber.alive? && task.state != :sleeping
        task.state = :ready
        @run_queue << task
      end
      true
    ensure
      @current = nil
    end

    def run
      while @run_queue.any? || @sleeping.any?
        if @run_queue.empty?
          delay = [@sleeping.map(&:wake_at).min - now_ms, 0].max
          @sleeper.call(delay) if delay.positive?
        end
        tick
      end
      self
    end

    def yield_now
      Fiber.yield
    end

    def sleep_for(milliseconds)
      raise Error, "sleep_for must run inside a scheduled task" unless @current
      duration = Float(milliseconds)
      raise ArgumentError, "sleep duration must not be negative" if duration.negative?
      @current.state = :sleeping
      @current.wake_at = now_ms + duration
      @sleeping << @current
      Fiber.yield
    end

    def tasks
      @tasks.dup.freeze
    end

    def uptime_ms
      now_ms
    end

    private

    def wake_sleepers
      ready, waiting = @sleeping.partition { |task| task.wake_at <= now_ms }
      @sleeping = waiting
      ready.each do |task|
        task.wake_at = nil
        task.state = :ready
        @run_queue << task
      end
    end

    def now_ms
      @monotonic_ms.call
    end

    def platform_monotonic_ms
      if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:monotonic_ns)
        RubyOS::HAL.monotonic_ns / 1_000_000.0
      else
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end
    end

    def platform_sleep(milliseconds)
      if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:sleep_us)
        RubyOS::HAL.sleep_us((milliseconds * 1_000).ceil)
      else
        ::Kernel.sleep(milliseconds / 1_000.0)
      end
    end
  end
end
