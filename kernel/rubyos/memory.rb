# frozen_string_literal: true

module RubyOS
  module Memory
    PAGE_SIZE = 4096

    class InvalidFrame < RubyOS::Error; end

    Snapshot = Data.define(:total_bytes, :free_bytes) do
      def used_bytes = total_bytes - free_bytes
      def free_pages = free_bytes / PAGE_SIZE
    end

    class PageFrame
      attr_reader :address, :size

      def initialize(address, size = PAGE_SIZE)
        @address = Integer(address)
        @size = Integer(size)
        @released = false
      end

      def released? = @released

      def release!
        raise InvalidFrame, "page frame already released" if released?

        @released = true
        self
      end
    end

    class HALBackend
      def total_bytes = RubyOS::HAL.heap_total_bytes
      def free_bytes = RubyOS::HAL.heap_free_bytes
      def allocate(size) = RubyOS::HAL.dma_alloc(size)
      def release(address) = RubyOS::HAL.dma_free(address)
    end

    class SimulatedBackend
      attr_reader :total_bytes, :free_bytes

      def initialize(total_bytes = 128 * 1024 * 1024)
        @total_bytes = Integer(total_bytes)
        @free_bytes = @total_bytes
        @next_address = PAGE_SIZE
        @allocations = {}
      end

      def allocate(size)
        size = Integer(size)
        raise NoMemoryError, "RubyOS simulated heap exhausted" if size > free_bytes

        address = @next_address
        @next_address += size
        @allocations[address] = size
        @free_bytes -= size
        address
      end

      def release(address)
        size = @allocations.delete(Integer(address))
        raise InvalidFrame, "unknown page frame" unless size

        @free_bytes += size
        nil
      end
    end

    class Manager
      def self.system
        backend = if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:heap_free_bytes)
                    HALBackend.new
                  else
                    SimulatedBackend.new
                  end
        new(backend:)
      end

      def initialize(backend:)
        @backend = backend
        @frames = {}
      end

      def snapshot
        Snapshot.new(total_bytes: @backend.total_bytes, free_bytes: @backend.free_bytes)
      end

      def allocate
        address = @backend.allocate(PAGE_SIZE)
        RubyOS.invariant((address % PAGE_SIZE).zero?, "allocator returned an unaligned page")
        frame = PageFrame.new(address)
        @frames[address] = frame
      end

      def allocate_many(count)
        count = Integer(count)
        raise ArgumentError, "page count must be non-negative" if count.negative?

        frames = []
        count.times { frames << allocate }
        frames
      rescue Exception
        release_many(frames) if frames
        raise
      end

      def release(frame)
        unless frame.is_a?(PageFrame) && @frames[frame.address].equal?(frame) && !frame.released?
          raise InvalidFrame, "page frame is not owned by this manager"
        end

        @backend.release(frame.address)
        @frames.delete(frame.address)
        frame.release!
      end

      def release_many(frames)
        frames.each { |frame| release(frame) }
        nil
      end
    end
  end
end
