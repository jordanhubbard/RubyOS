# frozen_string_literal: true

module RubyOS
  module Drivers
    class VirtioNet
      MMIO_BASE = 0x0a000000
      MMIO_STRIDE = 0x200
      MMIO_DEVICES = 32
      MAGIC = 0x74726976
      DEVICE_NETWORK = 1
      FEATURE_MAC = 1 << 5
      PAGE_SIZE = 4096
      QUEUE_SIZE = 64
      BUFFER_SIZE = 2048
      NETWORK_HEADER_SIZE = 10
      DESCRIPTOR_WRITE = 2

      class Queue
        attr_reader :last_used

        def initialize(device, index, version)
          @device = device
          @index = index
          @available_index = 0
          @last_used = 0
          descriptor_size = QUEUE_SIZE * 16
          available_size = 4 + QUEUE_SIZE * 2 + 2
          used_offset = align(descriptor_size + available_size)
          total = used_offset + 4 + QUEUE_SIZE * 8 + 2
          @descriptors = RubyOS::HAL.dma_alloc(total)
          @available = @descriptors + descriptor_size
          @used = @descriptors + used_offset

          write_device(0x030, index)
          RubyOS.invariant(read_device(0x034) >= QUEUE_SIZE, "virtio-net queue too small")
          write_device(0x038, QUEUE_SIZE)
          if version == 1
            write_device(0x03c, PAGE_SIZE)
            write_device(0x040, @descriptors >> 12)
          else
            address(0x080, @descriptors)
            address(0x090, @available)
            address(0x0a0, @used)
            write_device(0x044, 1)
          end
        end

        def descriptor(index, address, length, flags = 0)
          location = @descriptors + index * 16
          write64(location, address)
          RubyOS::HAL.mmio_write32(location + 8, length)
          RubyOS::HAL.mmio_write32(location + 12, flags)
        end

        def push(index)
          slot = @available_index % QUEUE_SIZE
          write16(@available + 4 + slot * 2, index)
          @available_index = (@available_index + 1) & 0xffff
          write16(@available + 2, @available_index)
        end

        def used?
          used_index != @last_used
        end

        def pop
          location = @used + 4 + (@last_used % QUEUE_SIZE) * 8
          descriptor = RubyOS::HAL.mmio_read32(location)
          length = RubyOS::HAL.mmio_read32(location + 4)
          @last_used = (@last_used + 1) & 0xffff
          [descriptor, length]
        end

        def notify
          write_device(0x050, @index)
        end

        private

        def used_index
          (RubyOS::HAL.mmio_read32(@used) >> 16) & 0xffff
        end

        def align(value)
          (value + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
        end

        def read_device(offset)
          RubyOS::HAL.mmio_read32(@device + offset)
        end

        def write_device(offset, value)
          RubyOS::HAL.mmio_write32(@device + offset, value)
        end

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

      attr_reader :mac

      def self.find
        MMIO_DEVICES.times do |index|
          candidate = new(MMIO_BASE + index * MMIO_STRIDE)
          return candidate if candidate.probe
        end
        raise Error, "VirtIO network device not found"
      end

      def initialize(base)
        @base = base
        @receive_buffers = {}
        @transmit_buffers = {}
        @transmit_free = []
      end

      def probe
        return false unless register(0x000) == MAGIC
        version = register(0x004)
        return false unless [1, 2].include?(version)
        return false unless register(0x008) == DEVICE_NETWORK

        write_register(0x070, 0)
        write_register(0x070, 1)
        write_register(0x070, 3)
        if version == 1
          write_register(0x028, PAGE_SIZE)
          features = register(0x010)
          write_register(0x020, features & FEATURE_MAC)
        else
          write_register(0x014, 0)
          features = register(0x010)
          write_register(0x024, 0)
          write_register(0x020, features & FEATURE_MAC)
          write_register(0x024, 1)
          write_register(0x020, 0)
        end
        write_register(0x070, 11)
        bytes = 6.times.map { |index| RubyOS::HAL.mmio_read8(@base + 0x100 + index) }
        bytes = [0x02, 0x52, 0x55, 0x42, 0x59, 0x01] if bytes.all?(&:zero?)
        @mac = Net::MACAddress.new(bytes.pack("C*"))

        @receive = Queue.new(@base, 0, version)
        @transmit = Queue.new(@base, 1, version)
        prime_receive
        prime_transmit
        write_register(0x070, 15)
        @receive.notify
        true
      end

      def send(frame)
        payload = "\0".b * NETWORK_HEADER_SIZE + String(frame).b
        raise Error, "Ethernet frame exceeds VirtIO buffer" if payload.bytesize > BUFFER_SIZE
        reclaim_transmit
        raise Error, "VirtIO transmit queue is full" if @transmit_free.empty?
        descriptor = @transmit_free.pop
        buffer = @transmit_buffers.fetch(descriptor)
        payload.each_byte.with_index { |byte, index| RubyOS::HAL.mmio_write8(buffer + index, byte) }
        @transmit.descriptor(descriptor, buffer, payload.bytesize)
        @transmit.push(descriptor)
        @transmit.notify
        self
      end

      def receive
        return nil unless @receive.used?
        descriptor, length = @receive.pop
        buffer = @receive_buffers.fetch(descriptor)
        bytes = String.new(capacity: length)
        length.times { |index| bytes << RubyOS::HAL.mmio_read8(buffer + index) }
        @receive.push(descriptor)
        @receive.notify
        return nil if bytes.bytesize <= NETWORK_HEADER_SIZE
        bytes.byteslice(NETWORK_HEADER_SIZE..)
      end

      private

      def prime_receive
        QUEUE_SIZE.times do |index|
          buffer = RubyOS::HAL.dma_alloc(BUFFER_SIZE)
          @receive_buffers[index] = buffer
          @receive.descriptor(index, buffer, BUFFER_SIZE, DESCRIPTOR_WRITE)
          @receive.push(index)
        end
      end

      def prime_transmit
        QUEUE_SIZE.times do |index|
          @transmit_buffers[index] = RubyOS::HAL.dma_alloc(BUFFER_SIZE)
          @transmit_free << index
        end
      end

      def reclaim_transmit
        while @transmit.used?
          descriptor, = @transmit.pop
          @transmit_free << descriptor unless @transmit_free.include?(descriptor)
        end
      end

      def register(offset)
        RubyOS::HAL.mmio_read32(@base + offset)
      end

      def write_register(offset, value)
        RubyOS::HAL.mmio_write32(@base + offset, value)
      end
    end
  end
end
