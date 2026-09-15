# frozen_string_literal: true

module RubyOS
  module Drivers
    class HDA
      VENDOR_INTEL = 0x8086
      DEVICE_ICH6 = 0x2668
      GCTL = 0x08
      STATESTS = 0x0e
      ICOI = 0x60
      ICII = 0x64
      ICIS = 0x68
      STREAM_BASE = 0x80
      STREAM_STRIDE = 0x20
      BUFFER_BYTES = 48_000
      FORMAT_48K_S16_STEREO = 0x11

      attr_reader :bytes_played

      def self.find
        32.times do |device|
          identity = RubyOS::HAL.pci_read32(0, device, 0, 0)
          next if (identity & 0xffff) == 0xffff
          next unless (identity & 0xffff) == VENDOR_INTEL && (identity >> 16) == DEVICE_ICH6

          driver = new(0, device, 0)
          return driver if driver.probe
        end
        nil
      end

      def initialize(bus, device, function)
        @bus = bus
        @device = device
        @function = function
        @bytes_played = 0
      end

      def probe
        bar = pci_read(0x10)
        return false if bar.zero? || (bar & 1) != 0

        command = pci_read(0x04)
        if (bar & ~0x0f) >= 0x4000_0000
          pci_write(0x04, command & ~2)
          pci_write(0x10, 0x3f00_0000)
          bar = pci_read(0x10)
        end
        @base = bar & ~0x0f
        pci_write(0x04, command | 0x0006)
        trace("BAR enabled")
        reset_controller
        trace("controller reset")
        codecs = read16(STATESTS)
        return false if codecs.zero?

        @codec = (0...15).find { |index| (codecs & (1 << index)) != 0 }
        @stream = STREAM_BASE + ((read16(0) >> 8) & 0x0f) * STREAM_STRIDE
        configure_codec
        trace("codec configured")
        configure_stream
        trace("stream configured")
        true
      end

      def play(pcm)
        raise ArgumentError, "sample rate must be 48000 Hz" unless pcm.rate == Sound::SAMPLE_RATE
        bytes = pcm.stereo_bytes
        length = [bytes.bytesize, BUFFER_BYTES].min
        RubyOS::HAL.dma_write(@buffer, bytes.byteslice(0, length))
        write32(@stream + 0x08, length)
        control = read32(@stream) & 0x00ff_ffff
        write32(@stream, control | 2)
        trace("DMA started")
        deadline = RubyOS::HAL.monotonic_ns + 2_000_000_000
        RubyOS::HAL.sleep_us(1_000) while read32(@stream + 0x04).zero? && RubyOS::HAL.monotonic_ns < deadline
        position = read32(@stream + 0x04)
        RubyOS.invariant(position.positive?, "HDA DMA position did not advance")
        @bytes_played += length
        length
      end

      private

      def trace(message) = HAL.serial_write("[RubyOS/x86_64] HDA: #{message}\n")

      def reset_controller
        write32(GCTL, read32(GCTL) & ~1)
        wait_until { (read32(GCTL) & 1).zero? }
        write32(GCTL, read32(GCTL) | 1)
        RubyOS.invariant(wait_until { (read32(GCTL) & 1) != 0 }, "HDA controller reset timed out")
        HAL.sleep_us(1_000)
      end

      def configure_codec
        verb(1, 0x70500)
        verb(2, 0x70500)
        verb(3, 0x70500)
        verb(2, 0x70610)
        verb(2, 0x20000 | FORMAT_48K_S16_STEREO)
        verb(3, 0x70740)
        verb(3, 0x70c02)
      end

      def configure_stream
        write32(@stream, 0)
        write32(@stream, 1)
        wait_until { (read32(@stream) & 1) != 0 }
        write32(@stream, 0)
        wait_until { (read32(@stream) & 1).zero? }
        @buffer = RubyOS::HAL.dma_alloc(BUFFER_BYTES)
        @bdl = RubyOS::HAL.dma_alloc(16)
        write32_at(@bdl, @buffer & 0xffff_ffff)
        write32_at(@bdl + 4, @buffer >> 32)
        write32_at(@bdl + 8, BUFFER_BYTES)
        write32_at(@bdl + 12, 1)
        write32(@stream + 0x18, @bdl & 0xffff_ffff)
        write32(@stream + 0x1c, @bdl >> 32)
        write32(@stream + 0x08, BUFFER_BYTES)
        write16(@stream + 0x0c, 0)
        write16(@stream + 0x12, FORMAT_48K_S16_STEREO)
        write32(@stream, 1 << 20)
      end

      def verb(node, payload)
        command = (@codec << 28) | (node << 20) | payload
        wait_until { (read16(ICIS) & 1).zero? }
        write32(ICOI, command)
        write16(ICIS, 1)
        RubyOS.invariant(wait_until { (read16(ICIS) & 2) != 0 }, "HDA codec verb timed out")
        response = read32(ICII)
        write16(ICIS, 2)
        response
      end

      def wait_until
        100_000.times { return true if yield }
        false
      end

      def pci_read(offset) = HAL.pci_read32(@bus, @device, @function, offset)
      def pci_write(offset, value) = HAL.pci_write32(@bus, @device, @function, offset, value)
      def read32(offset) = HAL.mmio_read32(@base + offset)
      def read16(offset) = HAL.mmio_read16(@base + offset)
      def write32(offset, value) = HAL.mmio_write32(@base + offset, value)
      def write16(offset, value) = HAL.mmio_write16(@base + offset, value)
      def write32_at(address, value) = HAL.mmio_write32(address, value)
    end
  end
end
