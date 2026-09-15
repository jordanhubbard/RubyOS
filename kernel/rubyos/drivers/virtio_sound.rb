# frozen_string_literal: true

module RubyOS
  module Drivers
    class VirtioSound
      BASE = 0x0a000000
      STRIDE = 0x200
      DEVICE_COUNT = 32
      MAGIC = 0x74726976
      DEVICE_SOUND = 25
      PAGE_SIZE = 4096
      QUEUE_SIZE = 16
      DESCRIPTOR_NEXT = 1
      DESCRIPTOR_WRITE = 2
      CONTROL_QUEUE = 0
      TX_QUEUE = 2
      SET_PARAMS = 0x0101
      PREPARE = 0x0102
      START = 0x0104
      STATUS_OK = 0x8000
      FORMAT_S16 = 5
      RATE_48KHZ = 7
      PERIOD_BYTES = 48_000

      class Queue
        attr_accessor :next_descriptor, :last_used
        attr_reader :descriptors, :available, :used

        def initialize(device, index, version)
          @device = device
          @index = index
          @next_descriptor = 0
          @available_index = 0
          @last_used = 0
          descriptor_size = QUEUE_SIZE * 16
          available_size = 4 + QUEUE_SIZE * 2 + 2
          used_offset = (descriptor_size + available_size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
          @descriptors = RubyOS::HAL.dma_alloc(used_offset + 4 + QUEUE_SIZE * 8 + 2)
          @available = descriptors + descriptor_size
          @used = descriptors + used_offset

          write_device(0x030, index)
          RubyOS.invariant(read_device(0x034) >= QUEUE_SIZE, "virtio-sound queue too small")
          write_device(0x038, QUEUE_SIZE)
          if version == 1
            write_device(0x03c, PAGE_SIZE)
            write_device(0x040, descriptors >> 12)
          else
            address(0x080, descriptors)
            address(0x090, available)
            address(0x0a0, used)
            write_device(0x044, 1)
          end
        end

        def take(count)
          Array.new(count) do
            descriptor = @next_descriptor
            @next_descriptor = (@next_descriptor + 1) % QUEUE_SIZE
            descriptor
          end
        end

        def descriptor(index, address, length, flags = 0, following = 0)
          location = descriptors + index * 16
          write64(location, address)
          RubyOS::HAL.mmio_write32(location + 8, length)
          RubyOS::HAL.mmio_write32(location + 12, (flags & 0xffff) | (following << 16))
        end

        def push(index)
          write16(available + 4 + (@available_index % QUEUE_SIZE) * 2, index)
          @available_index = (@available_index + 1) & 0xffff
          write16(available + 2, @available_index)
        end

        def used_index = (RubyOS::HAL.mmio_read32(used) >> 16) & 0xffff

        def complete_one
          deadline = RubyOS::HAL.monotonic_ns + 2_000_000_000
          RubyOS::HAL.sleep_us(100) while used_index == last_used && RubyOS::HAL.monotonic_ns < deadline
          return false if used_index == last_used

          @last_used = (@last_used + 1) & 0xffff
          true
        end

        def notify = write_device(0x050, @index)

        private

        def read_device(offset) = RubyOS::HAL.mmio_read32(@device + offset)
        def write_device(offset, value) = RubyOS::HAL.mmio_write32(@device + offset, value)

        def address(offset, value)
          write_device(offset, value & 0xffffffff)
          write_device(offset + 4, value >> 32)
        end

        def write16(address, value)
          RubyOS::HAL.mmio_write8(address, value & 0xff)
          RubyOS::HAL.mmio_write8(address + 1, value >> 8)
        end

        def write64(address, value)
          RubyOS::HAL.mmio_write32(address, value & 0xffffffff)
          RubyOS::HAL.mmio_write32(address + 4, value >> 32)
        end
      end

      attr_reader :bytes_played, :transfers

      def self.find
        DEVICE_COUNT.times do |index|
          device = new(BASE + index * STRIDE)
          return device if device.probe
        end
        nil
      end

      def initialize(base)
        @base = base
        @bytes_played = 0
        @transfers = 0
      end

      def probe
        return false unless register(0x000) == MAGIC && register(0x008) == DEVICE_SOUND
        version = register(0x004)
        return false unless [1, 2].include?(version)

        write_register(0x070, 0)
        write_register(0x070, 1)
        write_register(0x070, 3)
        if version == 1
          write_register(0x028, PAGE_SIZE)
          write_register(0x020, 0)
        else
          write_register(0x024, 0)
          write_register(0x020, 0)
          write_register(0x024, 1)
          write_register(0x020, 0)
        end
        write_register(0x070, 11)
        @control = Queue.new(@base, CONTROL_QUEUE, version)
        @transmit = Queue.new(@base, TX_QUEUE, version)
        @request = RubyOS::HAL.dma_alloc(64)
        @response = RubyOS::HAL.dma_alloc(64)
        @header = RubyOS::HAL.dma_alloc(4)
        @status = RubyOS::HAL.dma_alloc(8)
        @samples = RubyOS::HAL.dma_alloc(PERIOD_BYTES)
        write_register(0x070, 15)
        configure
      end

      def play(pcm)
        bytes = pcm.stereo_bytes
        raise ArgumentError, "sample rate must be 48000 Hz" unless pcm.rate == Sound::SAMPLE_RATE
        length = [bytes.bytesize, PERIOD_BYTES].min
        length.times { |index| RubyOS::HAL.mmio_write8(@samples + index, bytes.getbyte(index)) }
        put32(@header, 0, 0)
        first, data, status = @transmit.take(3)
        @transmit.descriptor(first, @header, 4, DESCRIPTOR_NEXT, data)
        @transmit.descriptor(data, @samples, length, DESCRIPTOR_NEXT, status)
        @transmit.descriptor(status, @status, 8, DESCRIPTOR_WRITE)
        @transmit.push(first)
        @transmit.notify
        RubyOS.invariant(@transmit.complete_one, "virtio-sound PCM transfer timed out")
        @bytes_played += length
        @transfers += 1
        length
      end

      def metrics = { bytes: bytes_played, transfers: }.freeze

      private

      def configure
        28.times { |index| RubyOS::HAL.mmio_write8(@request + index, 0) }
        put32(@request, 0, SET_PARAMS)
        put32(@request, 4, 0)
        put32(@request, 8, PERIOD_BYTES * 5)
        put32(@request, 12, PERIOD_BYTES)
        RubyOS::HAL.mmio_write8(@request + 20, 2)
        RubyOS::HAL.mmio_write8(@request + 21, FORMAT_S16)
        RubyOS::HAL.mmio_write8(@request + 22, RATE_48KHZ)
        return false unless control(28) == STATUS_OK

        put32(@request, 0, PREPARE)
        put32(@request, 4, 0)
        return false unless control(8) == STATUS_OK

        put32(@request, 0, START)
        control(8) == STATUS_OK
      end

      def control(length)
        first, response = @control.take(2)
        @control.descriptor(first, @request, length, DESCRIPTOR_NEXT, response)
        @control.descriptor(response, @response, 4, DESCRIPTOR_WRITE)
        @control.push(first)
        @control.notify
        return -1 unless @control.complete_one

        read32(@response)
      end

      def register(offset) = RubyOS::HAL.mmio_read32(@base + offset)
      def write_register(offset, value) = RubyOS::HAL.mmio_write32(@base + offset, value)

      def put32(address, offset, value)
        4.times { |index| RubyOS::HAL.mmio_write8(address + offset + index, (value >> (index * 8)) & 0xff) }
      end

      def read32(address)
        4.times.sum { |index| RubyOS::HAL.mmio_read8(address + index) << (index * 8) }
      end
    end
  end
end
