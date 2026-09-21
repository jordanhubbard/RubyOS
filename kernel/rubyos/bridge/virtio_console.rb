# frozen_string_literal: true

module RubyOS
  module Bridge
    module Transport
      class VirtioConsole
        MMIO_BASE = 0x0a000000
        MMIO_STRIDE = 0x200
        MMIO_DEVICES = 32
        MAGIC = 0x74726976
        DEVICE_CONSOLE = 3
        PAGE_SIZE = 4096
        QUEUE_SIZE = 16
        BUFFER_SIZE = 4096
        RX_QUEUE = 0
        TX_QUEUE = 1
        DESCRIPTOR_WRITE = 2

        class Queue
          attr_reader :last_used

          def initialize(device, index, version)
            @device = device
            @index = index
            @next_descriptor = 0
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
            maximum = read_device(0x034)
            RubyOS.invariant(maximum >= QUEUE_SIZE, "virtio-console queue too small")
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

          def next_descriptor
            descriptor = @next_descriptor
            @next_descriptor = (@next_descriptor + 1) % QUEUE_SIZE
            descriptor
          end

          def descriptor(index, address, length, flags = 0)
            location = @descriptors + index * 16
            write64(location, address)
            RubyOS::HAL.mmio_write32(location + 8, length)
            RubyOS::HAL.mmio_write32(location + 12, flags & 0xffff)
          end

          def push(index)
            slot = @available_index % QUEUE_SIZE
            write16(@available + 4 + slot * 2, index)
            @available_index = (@available_index + 1) & 0xffff
            write16(@available + 2, @available_index)
          end

          def used_index
            (RubyOS::HAL.mmio_read32(@used) >> 16) & 0xffff
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
            RubyOS::HAL.mmio_write8(address + 1, (value >> 8) & 0xff)
          end

          def write64(address, value)
            RubyOS::HAL.mmio_write32(address, value & 0xffffffff)
            RubyOS::HAL.mmio_write32(address + 4, value >> 32)
          end
        end

        def self.find
          MMIO_DEVICES.times do |index|
            device = new(MMIO_BASE + index * MMIO_STRIDE)
            return device if device.probe
          end
          raise Error.new(-1, "virtio-console bridge device not found")
        end

        def initialize(base)
          @base = base
          @receive_buffers = []
          @pending = +"".b
          @transmit_buffer = nil
          @transmit_buffer_size = 0
        end

        def probe
          return false unless read_register(0x000) == MAGIC
          version = read_register(0x004)
          return false unless [1, 2].include?(version)
          return false unless read_register(0x008) == DEVICE_CONSOLE

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
          @receive = Queue.new(@base, RX_QUEUE, version)
          @transmit = Queue.new(@base, TX_QUEUE, version)
          prime_receive
          write_register(0x070, 15)
          @receive.notify
          true
        end

        def write(bytes)
          bytes = String(bytes).b
          return self if bytes.empty?
          descriptor = @transmit.next_descriptor
          buffer = transmit_buffer(bytes.bytesize)
          bytes.each_byte.with_index do |byte, index|
            RubyOS::HAL.mmio_write8(buffer + index, byte)
          end
          @transmit.descriptor(descriptor, buffer, bytes.bytesize)
          @transmit.push(descriptor)
          @transmit.notify
          sleep_until { @transmit.used_index != @transmit.last_used }
          @transmit.pop
          self
        end

        # One bounce buffer, reused for every message and grown when a larger
        # one arrives.
        #
        # This used to dma_alloc per write and never free, leaking a
        # page-rounded buffer per bridge message; a session that draws enough
        # frames exhausts the guest heap and dies in whatever happens to
        # allocate next. Freeing each buffer instead would fix the leak but
        # hand the buddy allocator a churn of odd-sized blocks to fragment
        # over, so hold one instead. Writes are synchronous -- #write does not
        # return until the device has consumed the descriptor -- so there is
        # never a second message in flight to alias it.
        def transmit_buffer(size)
          if @transmit_buffer_size.to_i < size
            RubyOS::HAL.dma_free(@transmit_buffer) if @transmit_buffer
            @transmit_buffer = RubyOS::HAL.dma_alloc(size)
            @transmit_buffer_size = size
          end
          @transmit_buffer
        end

        def read_exact(length)
          while @pending.bytesize < length
            sleep_until { @receive.used_index != @receive.last_used }
            descriptor, received = @receive.pop
            buffer = @receive_buffers.fetch(descriptor)
            received.times { |index| @pending << RubyOS::HAL.mmio_read8(buffer + index) }
            @receive.push(descriptor)
            @receive.notify
          end
          bytes = @pending.byteslice(0, length)
          @pending = @pending.byteslice(length..) || +"".b
          bytes
        end

        def close
          self
        end

        private

        def read_register(offset)
          RubyOS::HAL.mmio_read32(@base + offset)
        end

        def write_register(offset, value)
          RubyOS::HAL.mmio_write32(@base + offset, value)
        end

        def prime_receive
          QUEUE_SIZE.times do |index|
            buffer = RubyOS::HAL.dma_alloc(BUFFER_SIZE)
            @receive_buffers << buffer
            @receive.descriptor(index, buffer, BUFFER_SIZE, DESCRIPTOR_WRITE)
            @receive.push(index)
          end
        end

        def sleep_until
          nil until yield
        end
      end
    end
  end
end
