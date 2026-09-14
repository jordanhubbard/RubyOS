# frozen_string_literal: true

module RubyOS
  # Cooperative kernel scheduler. A timer interrupt will eventually call
  # #tick; the hosted exploration drives it directly. Fibers make suspension
  # and resumption explicit and keep the design idiomatic Ruby.
  class Scheduler
    Task = Struct.new(:name, :fiber, :state, :result, :failure,
                      keyword_init: true)

    attr_reader :ticks

    def initialize
      @run_queue = []
      @tasks = []
      @ticks = 0
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
      task = Task.new(name:, fiber:, state: :ready, result: nil, failure: nil)
      @tasks << task
      @run_queue << task
      task
    end

    def tick
      @ticks += 1
      task = @run_queue.shift
      return false unless task

      task.fiber.resume if task.fiber.alive?
      @run_queue << task if task.fiber.alive?
      true
    end

    def run
      tick while @run_queue.any?
      self
    end

    def yield_now
      Fiber.yield
    end

    def tasks
      @tasks.dup.freeze
    end
  end
end
