# frozen_string_literal: true

module RubyOS
  module Drivers
    class VirtioBlock
      MMIO_BASE = 0x0a000000
      MMIO_STRIDE = 0x200
      MMIO_DEVICES = 32
      MAGIC = 0x74726976
      DEVICE_BLOCK = 2
      PAGE_SIZE = 4096
      QUEUE_SIZE = 16
      SECTOR_SIZE = 512
      DESCRIPTOR_NEXT = 1
      DESCRIPTOR_WRITE = 2
      REQUEST_READ = 0
      REQUEST_WRITE = 1

      attr_reader :size, :sector_count

      def self.find
        MMIO_DEVICES.times do |index|
          candidate = new(MMIO_BASE + index * MMIO_STRIDE)
          return candidate if candidate.probe
        end
        raise Error, "VirtIO block device not found"
      end

      def initialize(base)
        @base = base
        @available_index = 0
        @last_used = 0
      end

      def probe
        return false unless register(0x000) == MAGIC
        version = register(0x004)
        return false unless [1, 2].include?(version)
        return false unless register(0x008) == DEVICE_BLOCK

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

        @sector_count = register(0x100) | (register(0x104) << 32)
        @size = @sector_count * SECTOR_SIZE
        setup_queue(version)
        allocate_request
        write_register(0x070, 15)
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

      def write_sector(number, bytes)
        bytes = String(bytes).b
        raise ArgumentError, "sector must contain 512 bytes" unless bytes.bytesize == SECTOR_SIZE
        bytes_to_dma(@data, bytes)
        submit(REQUEST_WRITE, number)
        self
      end

      private

      def setup_queue(version)
        descriptor_size = QUEUE_SIZE * 16
        available_size = 4 + QUEUE_SIZE * 2 + 2
        used_offset = align(descriptor_size + available_size)
        total = used_offset + 4 + QUEUE_SIZE * 8 + 2
        @descriptors = RubyOS::HAL.dma_alloc(total)
        @available = @descriptors + descriptor_size
        @used = @descriptors + used_offset

        write_register(0x030, 0)
        RubyOS.invariant(register(0x034) >= QUEUE_SIZE, "virtio-block queue too small")
        write_register(0x038, QUEUE_SIZE)
        if version == 1
          write_register(0x03c, PAGE_SIZE)
          write_register(0x040, @descriptors >> 12)
        else
          write_address(0x080, @descriptors)
          write_address(0x090, @available)
          write_address(0x0a0, @used)
          write_register(0x044, 1)
        end
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
        write_register(0x050, 0)

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

      def register(offset)
        RubyOS::HAL.mmio_read32(@base + offset)
      end

      def write_register(offset, value)
        RubyOS::HAL.mmio_write32(@base + offset, value)
      end

      def write_address(offset, value)
        write_register(offset, value & 0xffffffff)
        write_register(offset + 4, value >> 32)
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
