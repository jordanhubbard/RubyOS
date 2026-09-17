# frozen_string_literal: true

module RubyOS
  # Cooperative synchronization built around Scheduler and Fiber.  These are
  # Ruby objects, Enumerable protocols and block scopes rather than a second
  # event-loop personality layered over the kernel.
  module Async
    class ClosedError < Error; end

    class Channel
      include Enumerable

      attr_reader :scheduler, :capacity

      def initialize(scheduler:, capacity: nil)
        @scheduler = scheduler
        @capacity = capacity.nil? ? nil : Integer(capacity)
        raise ArgumentError, "capacity must be positive" if @capacity && @capacity <= 0

        @values = []
        @closed = false
      end

      def send(value, timeout_ms: nil)
        raise ClosedError, "channel is closed" if closed?

        scheduler.wait_until(timeout_ms:) { closed? || !full? }
        raise ClosedError, "channel is closed" if closed?

        @values << value
        self
      end
      alias << send

      def receive(timeout_ms: nil)
        scheduler.wait_until(timeout_ms:) { !empty? || closed? }
        return @values.shift unless empty?

        raise ClosedError, "channel is closed"
      end
      alias pop receive

      def close
        @closed = true
        self
      end

      def closed? = @closed
      def empty? = @values.empty?
      def size = @values.length
      def full? = capacity && size >= capacity

      def each
        return enum_for(:each) unless block_given?

        loop do
          value = begin
            receive
          rescue ClosedError
            break
          end
          yield value
        end
        self
      end
    end

    class Event
      def initialize(scheduler:, set: false)
        @scheduler = scheduler
        @set = !!set
      end

      def set
        @set = true
        self
      end

      def clear
        @set = false
        self
      end

      def set? = @set

      def wait(timeout_ms: nil)
        @scheduler.wait_until(timeout_ms:) { set? }
        true
      end
    end

    class Semaphore
      attr_reader :limit, :available

      def initialize(scheduler:, limit: 1)
        @scheduler = scheduler
        @limit = Integer(limit)
        raise ArgumentError, "semaphore limit must be positive" unless @limit.positive?

        @available = @limit
      end

      def acquire(timeout_ms: nil)
        @scheduler.wait_until(timeout_ms:) { available.positive? }
        @available -= 1
        self
      end

      def release
        raise Error, "semaphore released without acquire" if available >= limit

        @available += 1
        self
      end

      def synchronize(timeout_ms: nil)
        acquired = false
        acquire(timeout_ms:)
        acquired = true
        yield
      ensure
        release if acquired
      end
    end

    class TaskGroup
      attr_reader :scheduler, :tasks

      def self.open(scheduler, timeout_ms: nil)
        group = new(scheduler)
        yield group
        group.wait(timeout_ms:)
      rescue Exception
        group&.cancel
        raise
      end

      def initialize(scheduler)
        @scheduler = scheduler
        @tasks = []
        @closed = false
      end

      def async(name = nil, &body)
        raise Error, "task group is closed" if @closed
        raise ArgumentError, "task body required" unless body

        label = name || "async-#{tasks.length + 1}"
        scheduler.spawn(label, &body).tap { |task| tasks << task }
      end

      def wait(timeout_ms: nil)
        @closed = true
        scheduler.gather(tasks, timeout_ms:)
      rescue Exception
        cancel
        raise
      end

      def cancel
        @closed = true
        tasks.each { |task| scheduler.kill(task) unless task.terminal? }
        self
      end

      def done? = tasks.all?(&:terminal?)
    end
  end
end
