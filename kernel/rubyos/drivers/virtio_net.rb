# frozen_string_literal: true

module RubyOS
  module Drivers
    class VirtioNet
      FEATURE_MAC = 1 << 5
      PAGE_SIZE = 4096
      QUEUE_SIZE = 64
      BUFFER_SIZE = 2048
      DESCRIPTOR_WRITE = 2

      class Queue
        attr_reader :last_used

        def initialize(device, index)
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

          @device.setup_queue(index, QUEUE_SIZE, @descriptors, @available, @used)
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
          @device.notify(@index)
        end

        private

        def used_index
          (RubyOS::HAL.mmio_read32(@used) >> 16) & 0xffff
        end

        def align(value)
          (value + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
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
        device = new(VirtioTransport.find(1))
        device.probe
        device
      end

      def initialize(transport)
        @transport = transport
        @receive_buffers = {}
        @transmit_buffers = {}
        @transmit_free = []
      end

      def probe
        features = @transport.negotiate(FEATURE_MAC)
        RubyOS.invariant(features & FEATURE_MAC != 0, "VirtIO MAC feature required")
        @header_size = @transport.modern? ? 12 : 10
        bytes = 6.times.map { |index| @transport.config8(index) }
        @mac = Net::MACAddress.new(bytes.pack("C*"))

        @receive = Queue.new(@transport, 0)
        @transmit = Queue.new(@transport, 1)
        prime_receive
        prime_transmit
        @transport.ready
        @receive.notify
        true
      end

      def send(frame)
        payload = "\0".b * @header_size + String(frame).b
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
        RubyOS.invariant(descriptor < QUEUE_SIZE && length <= BUFFER_SIZE,
                         "invalid VirtIO receive completion")
        buffer = @receive_buffers.fetch(descriptor)
        bytes = String.new(capacity: length)
        length.times { |index| bytes << RubyOS::HAL.mmio_read8(buffer + index) }
        @receive.push(descriptor)
        @receive.notify
        return nil if bytes.bytesize <= @header_size
        bytes.byteslice(@header_size..)
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

    end
  end
end
