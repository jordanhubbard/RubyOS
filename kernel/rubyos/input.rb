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
  end
end
