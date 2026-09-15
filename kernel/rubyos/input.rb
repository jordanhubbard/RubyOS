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
  end
end
