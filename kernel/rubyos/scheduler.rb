# frozen_string_literal: true

module RubyOS
  # Cooperative kernel scheduler. Hardware timer IRQs supply monotonic time;
  # Fibers switch at explicit Ruby scheduling points, matching PythonOS's
  # cooperative asyncio baseline without interrupting the CRuby VM unsafely.
  class Scheduler
    TICK_HZ = 100

    class TimeoutError < Error; end
    class TaskKilled < Error; end

    Task = Struct.new(:pid, :name, :fiber, :state, :result, :failure, :wake_at,
                      :ticks, :auto_reap, keyword_init: true) do
      def alive? = fiber.alive? && ![:killed, :complete, :failed].include?(state)
      def terminal? = [:killed, :complete, :failed].include?(state)
    end

    attr_reader :ticks

    def initialize(monotonic_ms: nil, sleeper: nil)
      @run_queue = []
      @sleeping = []
      @tasks = []
      @ticks = 0
      @next_pid = 1
      @current = nil
      @monotonic_ms = monotonic_ms || method(:platform_monotonic_ms)
      @sleeper = sleeper || method(:platform_sleep)
    end

    def spawn(name, auto_reap: false, &body)
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
      task = Task.new(pid: @next_pid, name:, fiber:, state: :ready, result: nil,
                      failure: nil, wake_at: nil, ticks: 0, auto_reap:)
      @next_pid += 1
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
      task.ticks += 1
      task.fiber.resume if task.fiber.alive?
      if task.fiber.alive? && task.state != :sleeping
        task.state = :ready
        @run_queue << task
      elsif task.auto_reap
        @tasks.delete(task)
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

    alias ps tasks

    def current_task = @current

    def wait_until(timeout_ms: nil)
      raise ArgumentError, "condition block required" unless block_given?

      timeout = timeout_ms.nil? ? nil : Float(timeout_ms)
      raise ArgumentError, "timeout must be finite and nonnegative" if
        timeout && (!timeout.finite? || timeout.negative?)
      deadline = timeout && now_ms + timeout
      loop do
        return true if yield
        raise TimeoutError, "operation timed out after #{timeout_ms} ms" if
          deadline && now_ms >= deadline
        raise Error, "waiting requires a scheduled task" unless current_task

        yield_now
      end
    end

    def join(task_or_pid, timeout_ms: nil)
      task = resolve_task(task_or_pid)
      raise ArgumentError, "unknown task" unless task
      raise Error, "task cannot join itself" if task.equal?(current_task)

      wait_until(timeout_ms:) { task.terminal? }
      raise task.failure if task.failure
      raise TaskKilled, "task #{task.pid} (#{task.name}) was killed" if task.state == :killed

      task.result
    end

    def gather(*task_values, timeout_ms: nil)
      selected = task_values.flatten.map do |task_or_pid|
        resolve_task(task_or_pid) || raise(ArgumentError, "unknown task")
      end
      raise Error, "task cannot gather itself" if selected.include?(current_task)

      wait_until(timeout_ms:) do
        selected.all?(&:terminal?) || selected.any?(&:failure) ||
          selected.any? { |task| task.state == :killed }
      end
      failed = selected.find(&:failure)
      raise failed.failure if failed
      killed = selected.find { |task| task.state == :killed }
      if killed
        raise TaskKilled, "task #{killed.pid} (#{killed.name}) was killed"
      end

      selected.map(&:result)
    end

    def kill(task_or_pid)
      task = resolve_task(task_or_pid)
      return false unless task && !task.terminal?

      @run_queue.delete(task)
      @sleeping.delete(task)
      task.state = :killed
      task.wake_at = nil
      true
    end

    def reap(task_or_pid)
      task = resolve_task(task_or_pid)
      return nil unless task&.terminal?

      @tasks.delete(task)
      task
    end

    def uptime_ms
      now_ms
    end

    private

    def resolve_task(task_or_pid)
      return task_or_pid if task_or_pid.is_a?(Task) && @tasks.include?(task_or_pid)

      pid = Integer(task_or_pid)
      @tasks.find { |task| task.pid == pid }
    rescue ArgumentError, TypeError
      nil
    end

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
