# frozen_string_literal: true

module RubyOS
  class Timekeeper
    DAY_SECONDS = 24 * 60 * 60

    def initialize(monotonic_ns: nil)
      @monotonic_ns = monotonic_ns || method(:platform_monotonic_ns)
      @boot_ns = @monotonic_ns.call
      @wall_base_seconds = nil
      @wall_base_ns = nil
    end

    def nanoseconds
      @monotonic_ns.call - @boot_ns
    end

    def milliseconds
      nanoseconds / 1_000_000
    end

    def sleep(milliseconds)
      duration = Float(milliseconds)
      raise ArgumentError, "sleep duration must not be negative" if duration.negative?

      if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:sleep_us)
        RubyOS::HAL.sleep_us((duration * 1_000).ceil)
      else
        ::Kernel.sleep(duration / 1_000.0)
      end
      self
    end

    def set_hms(hour, minute, second = 0)
      hour = Integer(hour)
      minute = Integer(minute)
      second = Integer(second)
      raise ArgumentError, "hour must be 00..23" unless (0..23).cover?(hour)
      raise ArgumentError, "minute must be 00..59" unless (0..59).cover?(minute)
      raise ArgumentError, "second must be 00..59" unless (0..59).cover?(second)

      @wall_base_seconds = hour * 3600 + minute * 60 + second
      @wall_base_ns = nanoseconds
      self
    end

    def clear_wall_clock
      @wall_base_seconds = nil
      @wall_base_ns = nil
      self
    end

    def wall_clock_set?
      !@wall_base_seconds.nil?
    end

    def seconds
      return nanoseconds / 1_000_000_000 unless wall_clock_set?

      (@wall_base_seconds + (nanoseconds - @wall_base_ns) / 1_000_000_000) % DAY_SECONDS
    end

    def format_hms
      value = seconds
      format("%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    end

    private

    def platform_monotonic_ns
      if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:monotonic_ns)
        RubyOS::HAL.monotonic_ns
      else
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      end
    end
  end
end
