# frozen_string_literal: true

module RubyOS
  module Input
    KEY_DOWN = 1
    KEY_UP = 2
    POINTER_MOVE = 3
    POINTER_DOWN = 4
    POINTER_UP = 5
    POINTER_WHEEL = 6
    FILE_DROP = 7
    QUIT = 100

    MOD_SHIFT = 1 << 0
    MOD_CTRL = 1 << 1
    MOD_ALT = 1 << 2
    MOD_META = 1 << 3
    MOD_CAPS = 1 << 4

    Event = Data.define(:kind, :code, :text, :mods, :x, :y, :dx, :dy,
                        :button, :name, :token, :size) do
      DEFAULTS = { code: 0, text: "", mods: 0, x: 0, y: 0, dx: 0, dy: 0,
                   button: 0, name: "", token: 0, size: 0 }.freeze

      def self.build(kind:, **attributes)
        new(**DEFAULTS.merge(attributes).merge(kind: Integer(kind)))
      end

      def self.from_bridge(document)
        values = DEFAULTS.to_h do |key, fallback|
          [key, document.fetch(key.to_s, fallback)]
        end
        build(kind: document.fetch("kind"), **values)
      end

      def fetch(key, default = (missing = true))
        name = key.to_sym
        return public_send(name) if members.include?(name)
        return default unless missing

        raise KeyError, "unknown input event field #{key.inspect}"
      end

      def [](key) = fetch(key)
    end

    class EventQueue
      attr_reader :capacity, :dropped

      def initialize(capacity: 256)
        @capacity = Integer(capacity)
        raise ArgumentError, "queue capacity must be positive" unless @capacity.positive?

        @events = []
        @dropped = 0
        @subscribers = []
      end

      def subscribe(&listener)
        raise ArgumentError, "listener required" unless listener

        @subscribers << listener
        self
      end

      def post(event)
        raise ArgumentError, "expected RubyOS::Input::Event" unless event.is_a?(Event)
        if @events.length == capacity
          @dropped += 1
          return false
        end

        @events << event
        @subscribers.each { |listener| listener.call(event) }
        true
      end

      def poll(limit = nil)
        count = limit.nil? ? @events.length : [Integer(limit), @events.length].min
        @events.shift(count)
      end

      def next_event = @events.shift
      def length = @events.length
      def empty? = @events.empty?
    end

    class PS2Keyboard
      SCANCODES = {
        0x01 => [27, "", ""], 0x0e => [8, "", ""], 0x0f => [9, "\t", "\t"],
        0x1c => [13, "\n", "\n"], 0x39 => [32, " ", " "],
        0x02 => [49, "1", "!"], 0x03 => [50, "2", "@"], 0x04 => [51, "3", "#"],
        0x05 => [52, "4", "$"], 0x06 => [53, "5", "%"], 0x07 => [54, "6", "^"],
        0x08 => [55, "7", "&"], 0x09 => [56, "8", "*"], 0x0a => [57, "9", "("],
        0x0b => [48, "0", ")"], 0x0c => [45, "-", "_"], 0x0d => [61, "=", "+"],
        0x10 => [113, "q", "Q"], 0x11 => [119, "w", "W"], 0x12 => [101, "e", "E"],
        0x13 => [114, "r", "R"], 0x14 => [116, "t", "T"], 0x15 => [121, "y", "Y"],
        0x16 => [117, "u", "U"], 0x17 => [105, "i", "I"], 0x18 => [111, "o", "O"],
        0x19 => [112, "p", "P"], 0x1e => [97, "a", "A"], 0x1f => [115, "s", "S"],
        0x20 => [100, "d", "D"], 0x21 => [102, "f", "F"], 0x22 => [103, "g", "G"],
        0x23 => [104, "h", "H"], 0x24 => [106, "j", "J"], 0x25 => [107, "k", "K"],
        0x26 => [108, "l", "L"], 0x2c => [122, "z", "Z"], 0x2d => [120, "x", "X"],
        0x2e => [99, "c", "C"], 0x2f => [118, "v", "V"], 0x30 => [98, "b", "B"],
        0x31 => [110, "n", "N"], 0x32 => [109, "m", "M"],
        0x33 => [44, ",", "<"], 0x34 => [46, ".", ">"], 0x35 => [47, "/", "?"]
      }.freeze
      MODIFIERS = { 0x2a => MOD_SHIFT, 0x36 => MOD_SHIFT,
                    0x1d => MOD_CTRL, 0x38 => MOD_ALT }.freeze

      attr_reader :mods

      def initialize
        @mods = 0
        @caps = false
      end

      def feed(scancode)
        byte = Integer(scancode) & 0xff
        released = (byte & 0x80) != 0
        code = byte & 0x7f
        if (modifier = MODIFIERS[code])
          @mods = released ? (@mods & ~modifier) : (@mods | modifier)
          return nil
        end
        if code == 0x3a
          @caps = !@caps unless released
          return nil
        end

        mapping = SCANCODES[code]
        return nil unless mapping

        key, plain, shifted = mapping
        upper = ((mods & MOD_SHIFT) != 0) ^ (@caps && plain.match?(/[a-z]/))
        Event.build(kind: released ? KEY_UP : KEY_DOWN, code: key,
                    text: released ? "" : (upper ? shifted : plain),
                    mods: mods | (@caps ? MOD_CAPS : 0))
      end
    end

    class PS2Mouse
      def initialize(x: 320, y: 200)
        @x = Integer(x)
        @y = Integer(y)
        @packet = []
        @buttons = 0
      end

      def feed(byte)
        byte = Integer(byte) & 0xff
        @packet.clear if @packet.empty? && (byte & 0x08).zero?
        @packet << byte
        return [] until @packet.length == 3

        flags, raw_x, raw_y = @packet
        @packet = []
        return [] if (flags & 0x08).zero?

        dx = (flags & 0x10).zero? ? raw_x : raw_x - 256
        dy = -((flags & 0x20).zero? ? raw_y : raw_y - 256)
        @x = [@x + dx, 0].max
        @y = [@y + dy, 0].max
        events = []
        events << Event.build(kind: POINTER_MOVE, x: @x, y: @y, dx:, dy:) unless dx.zero? && dy.zero?
        changed = @buttons ^ (flags & 7)
        { 1 => 1, 4 => 2, 2 => 3 }.each do |mask, button|
          next if (changed & mask).zero?

          pressed = (flags & mask) != 0
          events << Event.build(kind: pressed ? POINTER_DOWN : POINTER_UP,
                                button:, x: @x, y: @y)
        end
        @buttons = flags & 7
        events
      end
    end

    class VirtioKeyboardTranslator
      CHARACTERS = {
        2 => ["1", "!"], 3 => ["2", "@"], 4 => ["3", "#"], 5 => ["4", "$"],
        6 => ["5", "%"], 7 => ["6", "^"], 8 => ["7", "&"], 9 => ["8", "*"],
        10 => ["9", "("], 11 => ["0", ")"], 12 => ["-", "_"], 13 => ["=", "+"],
        16 => ["q", "Q"], 17 => ["w", "W"], 18 => ["e", "E"], 19 => ["r", "R"],
        20 => ["t", "T"], 21 => ["y", "Y"], 22 => ["u", "U"], 23 => ["i", "I"],
        24 => ["o", "O"], 25 => ["p", "P"], 30 => ["a", "A"], 31 => ["s", "S"],
        32 => ["d", "D"], 33 => ["f", "F"], 34 => ["g", "G"], 35 => ["h", "H"],
        36 => ["j", "J"], 37 => ["k", "K"], 38 => ["l", "L"], 44 => ["z", "Z"],
        45 => ["x", "X"], 46 => ["c", "C"], 47 => ["v", "V"], 48 => ["b", "B"],
        49 => ["n", "N"], 50 => ["m", "M"], 51 => [",", "<"], 52 => [".", ">"],
        53 => ["/", "?"], 57 => [" ", " "]
      }.freeze
      SPECIAL = {
        1 => 27, 14 => 8, 15 => 9, 28 => 13,
        102 => 1_073_741_898, 103 => 1_073_741_906,
        105 => 1_073_741_904, 106 => 1_073_741_903,
        107 => 1_073_741_897, 108 => 1_073_741_905,
        111 => 127
      }.freeze
      MODIFIERS = { 42 => MOD_SHIFT, 54 => MOD_SHIFT,
                    29 => MOD_CTRL, 97 => MOD_CTRL,
                    56 => MOD_ALT, 100 => MOD_ALT }.freeze

      attr_reader :mods

      def initialize
        @mods = 0
        @x = 320
        @y = 200
        @dx = 0
        @dy = 0
      end

      def translate(type, code, value)
        type = Integer(type)
        if type == 2
          delta = Integer(value)
          delta -= 1 << 32 if (delta & (1 << 31)) != 0
          @dx += delta if code == 0
          @dy += delta if code == 1
          return nil
        end
        if type.zero?
          return nil if @dx.zero? && @dy.zero?

          @x = [@x + @dx, 0].max
          @y = [@y + @dy, 0].max
          event = Event.build(kind: POINTER_MOVE, x: @x, y: @y, dx: @dx, dy: @dy)
          @dx = @dy = 0
          return event
        end
        return nil unless type == 1

        pressed = Integer(value) != 0
        if code.between?(0x110, 0x112)
          buttons = { 0x110 => 1, 0x112 => 2, 0x111 => 3 }
          return Event.build(kind: pressed ? POINTER_DOWN : POINTER_UP,
                             button: buttons.fetch(code), x: @x, y: @y)
        end
        if (modifier = MODIFIERS[code])
          @mods = pressed ? (@mods | modifier) : (@mods & ~modifier)
          return Event.build(kind: pressed ? KEY_DOWN : KEY_UP, code:, mods:)
        end
        if (characters = CHARACTERS[code])
          text = (mods & MOD_SHIFT) != 0 ? characters.last : characters.first
          return Event.build(kind: pressed ? KEY_DOWN : KEY_UP, code: text.downcase.ord,
                             text: pressed ? text : "", mods:)
        end
        key = SPECIAL[code]
        return nil unless key

        Event.build(kind: pressed ? KEY_DOWN : KEY_UP, code: key,
                    text: pressed && key == 13 ? "\n" : "", mods:)
      end
    end

    class VirtioMMIO
      BASE = 0x0a000000
      STRIDE = 0x200
      DEVICE_COUNT = 32
      MAGIC = 0x74726976
      DEVICE_INPUT = 18
      QUEUE_SIZE = 32
      EVENT_SIZE = 8
      PAGE_SIZE = 4096
      DESCRIPTOR_WRITE = 2

      def self.find
        find_all.first
      end

      def self.find_all
        DEVICE_COUNT.times.filter_map do |index|
          device = new(BASE + index * STRIDE)
          device if device.probe
        end
      end

      def initialize(base)
        @base = base
        @translator = VirtioKeyboardTranslator.new
        @available_index = 0
        @last_used = 0
      end

      def probe
        return false unless register(0x000) == MAGIC && register(0x008) == DEVICE_INPUT
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
        setup_queue(version)
        write_register(0x070, 15)
        write_register(0x050, 0)
        true
      end

      def poll
        events = []
        while @last_used != used_index
          slot = @last_used % QUEUE_SIZE
          descriptor = RubyOS::HAL.mmio_read32(@used + 4 + slot * 8)
          @last_used = (@last_used + 1) & 0xffff
          address = @buffers + descriptor * EVENT_SIZE
          type = read16(address)
          code = read16(address + 2)
          value = RubyOS::HAL.mmio_read32(address + 4)
          event = @translator.translate(type, code, value)
          events << event if event
          push(descriptor)
        end
        write_register(0x050, 0) unless events.empty?
        events
      end

      private

      def setup_queue(version)
        descriptor_size = QUEUE_SIZE * 16
        available_size = 4 + QUEUE_SIZE * 2 + 2
        used_offset = (descriptor_size + available_size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)
        @descriptors = RubyOS::HAL.dma_alloc(used_offset + 4 + QUEUE_SIZE * 8 + 2)
        @available = @descriptors + descriptor_size
        @used = @descriptors + used_offset
        @buffers = RubyOS::HAL.dma_alloc(QUEUE_SIZE * EVENT_SIZE)
        write_register(0x030, 0)
        RubyOS.invariant(register(0x034) >= QUEUE_SIZE, "virtio-input queue too small")
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
        QUEUE_SIZE.times do |index|
          location = @descriptors + index * 16
          write64(location, @buffers + index * EVENT_SIZE)
          RubyOS::HAL.mmio_write32(location + 8, EVENT_SIZE)
          RubyOS::HAL.mmio_write32(location + 12, DESCRIPTOR_WRITE)
          push(index)
        end
      end

      def push(descriptor)
        write16(@available + 4 + (@available_index % QUEUE_SIZE) * 2, descriptor)
        @available_index = (@available_index + 1) & 0xffff
        write16(@available + 2, @available_index)
      end

      def used_index = (RubyOS::HAL.mmio_read32(@used) >> 16) & 0xffff
      def register(offset) = RubyOS::HAL.mmio_read32(@base + offset)
      def write_register(offset, value) = RubyOS::HAL.mmio_write32(@base + offset, value)

      def read16(address)
        RubyOS::HAL.mmio_read8(address) | (RubyOS::HAL.mmio_read8(address + 1) << 8)
      end

      def write16(address, value)
        RubyOS::HAL.mmio_write8(address, value & 0xff)
        RubyOS::HAL.mmio_write8(address + 1, value >> 8)
      end

      def write64(address, value)
        RubyOS::HAL.mmio_write32(address, value & 0xffffffff)
        RubyOS::HAL.mmio_write32(address + 4, value >> 32)
      end

      def write_address(offset, address)
        write_register(offset, address & 0xffffffff)
        write_register(offset + 4, address >> 32)
      end
    end
  end
end
