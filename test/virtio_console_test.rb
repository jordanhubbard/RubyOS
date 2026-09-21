# frozen_string_literal: true

# DMA buffer lifetime for the virtio-console bridge transport.
#
# This transport used to dma_alloc a page-rounded buffer for every message it
# wrote and never free it. Nothing noticed for a long time because the leak is
# only fatal once a session writes enough messages -- a desktop drawing frames
# does, and the bare-metal GUI smoke died in whatever happened to allocate
# next, with a traceback pointing at innocent code. The invariant worth
# holding is that writing is O(1) in live DMA allocations, so assert that
# directly rather than the absence of one particular crash.

require "rubyos"
# Guest-only: it needs HAL, so kernel/rubyos.rb does not require it and the
# embed manifest carries it instead.
require "rubyos/bridge/virtio_console"

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

# Track every allocation so a leak shows up as a live handle, not as
# exhaustion after some unknown number of iterations.
module RubyOS::HAL
  class << self
    attr_accessor :live, :allocations, :frees, :next_address

    def reset_dma
      self.live = {}
      self.allocations = 0
      self.frees = 0
      self.next_address = 0x4000_0000
    end

    def dma_alloc(size)
      size = Integer(size)
      raise ArgumentError, "invalid DMA size" unless size.positive?

      rounded = (size + 4095) & ~4095
      address = self.next_address
      self.next_address += rounded
      live[address] = rounded
      self.allocations += 1
      address
    end

    def dma_free(address)
      assert(live.key?(address), "freeing an address that was never allocated")
      live.delete(address)
      self.frees += 1
      nil
    end

    def mmio_write8(_address, _value) = nil
    def mmio_read8(_address) = 0
  end
end

HAL = RubyOS::HAL
Console = RubyOS::Bridge::Transport::VirtioConsole

HAL.reset_dma
console = Console.allocate
console.send(:initialize, 0x0a00_0000)

buffer = console.send(:transmit_buffer, 64)
assert(HAL.allocations == 1, "the first write allocates a buffer")
assert(HAL.live.length == 1, "exactly one buffer is live")

# The leak: every message used to take a fresh buffer. Same-or-smaller
# messages must reuse the one already held.
2_000.times { |i| assert(console.send(:transmit_buffer, 1 + i % 64) == buffer, "reused at #{i}") }
assert(HAL.allocations == 1, "2000 further writes allocated nothing, got #{HAL.allocations}")
assert(HAL.live.length == 1, "still exactly one live buffer")

# A larger message has to grow, and the old buffer must be released rather
# than dropped on the floor.
larger = console.send(:transmit_buffer, 500_000)
assert(larger != buffer, "a larger message gets a new buffer")
assert(HAL.allocations == 2, "growing allocated once")
assert(HAL.frees == 1, "growing freed the buffer it replaced")
assert(HAL.live.length == 1, "growing leaves exactly one live buffer")
assert(HAL.live.key?(larger), "the live buffer is the new one")

# Having grown, it must not shrink back and start churning.
assert(console.send(:transmit_buffer, 64) == larger, "a small message reuses the grown buffer")
assert(HAL.allocations == 2, "shrinking does not reallocate")

# Growth is monotonic across many increasing sizes: one allocation each, and
# never more than one buffer alive.
before = HAL.allocations
(1..20).each do |step|
  console.send(:transmit_buffer, 500_000 + step * 4_096)
  assert(HAL.live.length == 1, "one live buffer after growth #{step}")
end
assert(HAL.allocations - before == 20, "each growth allocated exactly once")
assert(HAL.frees == HAL.allocations - 1, "every superseded buffer was freed")

# An empty message never reaches the buffer at all -- #write returns early --
# and a zero-length allocation would be rejected by the real HAL anyway.
assert(HAL.live.length == 1, "no stray allocations remain")

puts "RubyOS virtio-console DMA buffer lifetime: PASS"
