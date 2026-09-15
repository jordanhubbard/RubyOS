# frozen_string_literal: true

module RubyOS
  module Drivers
    class VirtioBlock
      PAGE_SIZE = 4096
      QUEUE_SIZE = 16
      SECTOR_SIZE = 512
      DESCRIPTOR_NEXT = 1
      DESCRIPTOR_WRITE = 2
      REQUEST_READ = 0
      REQUEST_WRITE = 1

      attr_reader :size, :sector_count

      def self.find
        device = new(VirtioTransport.find(2))
        device.probe
        device
      end

      def initialize(transport)
        @transport = transport
        @available_index = 0
        @last_used = 0
      end

      def probe
        @transport.negotiate(0)

        @sector_count = @transport.config32(0) | (@transport.config32(4) << 32)
        @size = @sector_count * SECTOR_SIZE
        setup_queue
        allocate_request
        @transport.ready
        true
      end

      def read(offset, length)
        raise RangeError, "block read outside device" if offset.negative? || offset + length > size
        output = +"".b
        until length.zero?
          sector_number = offset / SECTOR_SIZE
          within = offset % SECTOR_SIZE
          count = [length, SECTOR_SIZE - within].min
          output << read_sector(sector_number).byteslice(within, count)
          offset += count
          length -= count
        end
        output
      end

      def read_sector(number)
        submit(REQUEST_READ, number)
        bytes_from_dma(@data, SECTOR_SIZE)
      end

      def write(offset, bytes)
        bytes = String(bytes).b
        raise RangeError, "block write outside device" if offset.negative? || offset + bytes.bytesize > size
        until bytes.empty?
          sector_number = offset / SECTOR_SIZE
          within = offset % SECTOR_SIZE
          count = [bytes.bytesize, SECTOR_SIZE - within].min
          sector = within.zero? && count == SECTOR_SIZE ? bytes.byteslice(0, count) : read_sector(sector_number)
          sector[within, count] = bytes.byteslice(0, count) unless within.zero? && count == SECTOR_SIZE
          write_sector(sector_number, sector)
          offset += count
          bytes = bytes.byteslice(count..) || +"".b
        end
        self
      end

      def write_sector(number, bytes)
        bytes = String(bytes).b
        raise ArgumentError, "sector must contain 512 bytes" unless bytes.bytesize == SECTOR_SIZE
        bytes_to_dma(@data, bytes)
        submit(REQUEST_WRITE, number)
        self
      end

      private

      def setup_queue
        descriptor_size = QUEUE_SIZE * 16
        available_size = 4 + QUEUE_SIZE * 2 + 2
        used_offset = align(descriptor_size + available_size)
        total = used_offset + 4 + QUEUE_SIZE * 8 + 2
        @descriptors = RubyOS::HAL.dma_alloc(total)
        @available = @descriptors + descriptor_size
        @used = @descriptors + used_offset

        @transport.setup_queue(0, QUEUE_SIZE, @descriptors, @available, @used)
      end

      def allocate_request
        @header = RubyOS::HAL.dma_alloc(16)
        @data = RubyOS::HAL.dma_alloc(SECTOR_SIZE)
        @status = RubyOS::HAL.dma_alloc(4)
      end

      def submit(operation, sector)
        RubyOS::HAL.mmio_write32(@header, operation)
        RubyOS::HAL.mmio_write32(@header + 4, 0)
        write64(@header + 8, sector)
        RubyOS::HAL.mmio_write8(@status, 0xff)
        descriptor(0, @header, 16, DESCRIPTOR_NEXT, 1)
        data_flags = DESCRIPTOR_NEXT
        data_flags |= DESCRIPTOR_WRITE if operation == REQUEST_READ
        descriptor(1, @data, SECTOR_SIZE, data_flags, 2)
        descriptor(2, @status, 1, DESCRIPTOR_WRITE, 0)
        push(0)
        @transport.notify(0)

        deadline = RubyOS::HAL.monotonic_ns + 5_000_000_000
        until used_index != @last_used
          raise Error, "VirtIO block request timed out" if RubyOS::HAL.monotonic_ns >= deadline
        end
        @last_used = (@last_used + 1) & 0xffff
        status = RubyOS::HAL.mmio_read8(@status)
        raise Error, "VirtIO block request failed with status #{status}" unless status.zero?
      end

      def descriptor(index, address, length, flags, following)
        location = @descriptors + index * 16
        write64(location, address)
        RubyOS::HAL.mmio_write32(location + 8, length)
        RubyOS::HAL.mmio_write32(location + 12, (flags & 0xffff) | (following << 16))
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

      def bytes_from_dma(address, length)
        String.new(capacity: length).tap do |bytes|
          length.times { |index| bytes << RubyOS::HAL.mmio_read8(address + index) }
        end
      end

      def bytes_to_dma(address, bytes)
        bytes.each_byte.with_index { |byte, index| RubyOS::HAL.mmio_write8(address + index, byte) }
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
  end
end
