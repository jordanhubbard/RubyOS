# frozen_string_literal: true
require "rubyos"

module RubyOS::HAL
  class << self
    attr_accessor :pci_config, :memory, :features, :reject_features
    def reset
      self.pci_config = {}
      self.memory = Hash.new(0)
      self.features = true
      self.reject_features = false
    end
    def pci_read32(bus, slot, function, offset)
      slot == 3 ? pci_config.fetch(offset, 0) : 0xffffffff
    end
    def pci_write32(bus, slot, function, offset, value)
      pci_config[offset] = value
    end
    def mmio_read8(address) = memory[address]
    def mmio_write8(address, value)
      memory[address] = reject_features && address == 0x10014 && value == 11 ? 3 : value
    end
    def mmio_read16(address) = 2.times.sum { |i| memory[address + i] << (i * 8) }
    def mmio_write16(address, value)
      2.times { |i| memory[address + i] = value >> (i * 8) & 0xff }
    end
    def mmio_read32(address)
      return mmio_read32(0x10000).zero? ? 32 : (features ? 1 : 0) if address == 0x10004
      4.times.sum { |i| memory[address + i] << (i * 8) }
    end
    def mmio_write32(address, value)
      4.times { |i| memory[address + i] = value >> (i * 8) & 0xff }
    end
    def monotonic_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  end
end

HAL = RubyOS::HAL
def fixture
  HAL.reset
  HAL.pci_config.merge!(0 => 0x10411af4, 4 => 0, 0x10 => 0x10000, 0x34 => 0x40,
    0x40 => 0x01105009, 0x44 => 0, 0x48 => 0, 0x4c => 56,
    0x50 => 0x02146409, 0x54 => 0, 0x58 => 0x100, 0x5c => 32, 0x60 => 4,
    0x64 => 0x04100009, 0x68 => 0, 0x6c => 0x200, 0x70 => 8)
  HAL.mmio_write16(0x10018, 64)
  HAL.mmio_write16(0x1001e, 3)
  RubyOS::Drivers::VirtioTransport.find(1)
end

def rejects
  yield
  raise "invalid transport accepted"
rescue RubyOS::InvariantError
  nil
end

device = fixture
raise unless device.negotiate(32) == 32
raise unless HAL.memory[0x10014] == 11 && HAL.pci_config[4] == 0x406
device.setup_queue(1, 64, 0x200000, 0x201000, 0x202000)
raise unless HAL.mmio_read16(0x10016) == 1 && HAL.mmio_read16(0x1001c) == 1
raise unless HAL.mmio_read32(0x10020) == 0x200000
raise unless HAL.mmio_read32(0x10028) == 0x201000
raise unless HAL.mmio_read32(0x10030) == 0x202000
device.notify(1)
raise unless HAL.mmio_read16(0x1010c) == 1
device.ready
raise unless HAL.memory[0x10014] == 15
rejects { device.config32(6) }
device = fixture
HAL.features = false
rejects { device.negotiate(32) }
device = fixture
HAL.reject_features = true
rejects { device.negotiate(32) }
device = fixture
HAL.mmio_write16(0x1001e, 100)
rejects { device.setup_queue(0, 64, 0, 0, 0) }
fixture
HAL.pci_config[0x64] = 0x04104009
rejects { RubyOS::Drivers::VirtioTransport.find(1) }
puts "RubyOS VirtIO PCI capabilities, negotiation and queues: PASS"
