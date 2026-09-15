# frozen_string_literal: true

module RubyOS
  module Drivers
    # Device-independent VirtIO transport. Rings and device policy stay Ruby.
    # PCI layout: OASIS VirtIO 1.2, sections 4.1.4 and 4.1.5.
    module VirtioTransport
      def self.find(kind)
        if HAL.respond_to?(:pci_read32)
          32.times do |slot|
            identity = HAL.pci_read32(0, slot, 0, 0)
            next unless identity == ((0x1040 + kind) << 16 | 0x1af4)
            return PCI.new(slot)
          end
        else
          32.times do |slot|
            base = 0x0a000000 + slot * 0x200
            next unless HAL.mmio_read32(base) == 0x74726976
            next unless HAL.mmio_read32(base + 8) == kind
            return MMIO.new(base)
          end
        end
        raise Error, "VirtIO device #{kind} not found"
      end

      class MMIO
        def initialize(base)
          @base = base
          @version = read(4)
          RubyOS.invariant([1, 2].include?(@version), "unsupported VirtIO MMIO version")
        end

        def modern? = @version == 2
        def read(offset) = HAL.mmio_read32(@base + offset)
        def write(offset, value) = HAL.mmio_write32(@base + offset, value)
        def config8(offset) = HAL.mmio_read8(@base + 0x100 + offset)
        def config32(offset) = read(0x100 + offset)

        def negotiate(wanted)
          write(0x070, 0)
          write(0x070, 1)
          write(0x070, 3)
          write(0x014, 0) if modern?
          accepted = read(0x010) & wanted
          write(0x024, 0) if modern?
          write(0x020, accepted)
          if modern?
            write(0x014, 1)
            RubyOS.invariant(read(0x010) & 1 == 1, "VirtIO VERSION_1 missing")
            write(0x024, 1)
            write(0x020, 1)
            write(0x070, 11)
            RubyOS.invariant(read(0x070) & 8 == 8, "VirtIO features rejected")
          else
            write(0x028, 4096)
          end
          accepted
        end

        def setup_queue(index, size, descriptors, available, used)
          write(0x030, index)
          RubyOS.invariant(read(0x034) >= size, "VirtIO queue too small")
          write(0x038, size)
          if modern?
            [[0x080, descriptors], [0x090, available], [0x0a0, used]].each do |offset, address|
              write(offset, address & 0xffffffff)
              write(offset + 4, address >> 32)
            end
            write(0x044, 1)
          else
            write(0x03c, 4096)
            write(0x040, descriptors >> 12)
          end
        end

        def ready = write(0x070, modern? ? 15 : 7)
        def notify(index) = write(0x050, index)
      end

      class PCI
        def initialize(slot)
          @slot = slot
          @notifications = {}
          capabilities = {}
          pointer = pci(0x34) & 0xff
          seen = {}
          until pointer.zero?
            RubyOS.invariant(pointer >= 0x40 && pointer <= 0xfc && !seen[pointer], "invalid PCI capability chain")
            seen[pointer] = true
            header = pci(pointer)
            if header & 0xff == 9
              kind = header >> 24
              if [1, 2, 4].include?(kind)
                RubyOS.invariant((header >> 16 & 0xff) >= (kind == 2 ? 20 : 16), "short VirtIO capability")
                bar_index = pci(pointer + 4) & 0xff
                RubyOS.invariant(bar_index < 6, "invalid VirtIO BAR")
                low = pci(0x10 + bar_index * 4)
                RubyOS.invariant(low & 1 == 0, "VirtIO requires memory BAR")
                base = low & ~15
                base |= pci(0x14 + bar_index * 4) << 32 if low & 6 == 4
                offset = pci(pointer + 8)
                length = pci(pointer + 12)
                RubyOS.invariant(base.positive? && base + offset + length <= 0x1_0000_0000, "VirtIO BAR outside mapped physical memory")
                capabilities[kind] = [base + offset, length]
                @multiplier = pci(pointer + 16) if kind == 2
              end
            end
            pointer = header >> 8 & 0xff
          end
          RubyOS.invariant([1, 2, 4].all? { |kind| capabilities.key?(kind) }, "missing VirtIO PCI capabilities")
          @common, common_length = capabilities.fetch(1)
          @notify, @notify_length = capabilities.fetch(2)
          @config, @config_length = capabilities.fetch(4)
          RubyOS.invariant(common_length >= 56, "short VirtIO common configuration")
          # Enable memory and bus mastering; disable unused INTx (polled rings).
          HAL.pci_write32(0, @slot, 0, 4, (pci(4) & 0xffff) | 0x406)
        end

        def modern? = true
        def pci(offset) = HAL.pci_read32(0, @slot, 0, offset)
        def read32(offset) = HAL.mmio_read32(@common + offset)
        def write32(offset, value) = HAL.mmio_write32(@common + offset, value)
        def read16(offset) = HAL.mmio_read16(@common + offset)
        def write16(offset, value) = HAL.mmio_write16(@common + offset, value)
        def status = HAL.mmio_read8(@common + 20)
        def status=(value)
          HAL.mmio_write8(@common + 20, value)
        end

        def config8(offset)
          RubyOS.invariant(offset >= 0 && offset < @config_length, "VirtIO config outside BAR")
          HAL.mmio_read8(@config + offset)
        end

        def config32(offset)
          RubyOS.invariant(offset >= 0 && offset + 4 <= @config_length, "VirtIO config outside BAR")
          HAL.mmio_read32(@config + offset)
        end

        def negotiate(wanted)
          self.status = 0
          deadline = HAL.monotonic_ns + 1_000_000_000
          until status.zero?
            raise Error, "VirtIO reset timed out" if HAL.monotonic_ns >= deadline
          end
          self.status = 1
          self.status = 3
          write32(0, 0)
          accepted = read32(4) & wanted
          write32(8, 0)
          write32(12, accepted)
          write32(0, 1)
          RubyOS.invariant(read32(4) & 1 == 1, "VirtIO VERSION_1 missing")
          write32(8, 1)
          write32(12, 1)
          self.status = 11
          RubyOS.invariant(status & 8 == 8, "VirtIO features rejected")
          accepted
        end

        def setup_queue(index, size, descriptors, available, used)
          write16(22, index)
          RubyOS.invariant(read16(24) >= size && read16(28).zero?, "VirtIO queue unavailable")
          write16(24, size)
          write16(26, 0xffff)
          [[32, descriptors], [40, available], [48, used]].each do |offset, address|
            write32(offset, address & 0xffffffff)
            write32(offset + 4, address >> 32)
          end
          offset = read16(30) * @multiplier
          RubyOS.invariant(offset + 2 <= @notify_length, "VirtIO notification outside BAR")
          @notifications[index] = @notify + offset
          write16(28, 1)
        end

        def ready
          self.status = 15
        end

        def notify(index) = HAL.mmio_write16(@notifications.fetch(index), index)
      end
    end
  end
end
