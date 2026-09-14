# frozen_string_literal: true

module RubyOS
  module Net
    class Address
      include Comparable
      attr_reader :bytes

      def initialize(bytes, length:)
        @bytes = String(bytes).b
        raise ArgumentError, "address must contain #{length} bytes" unless @bytes.bytesize == length
        @bytes.freeze
        freeze
      end

      def <=>(other)
        bytes <=> other.bytes
      end

      def ==(other)
        other.instance_of?(self.class) && bytes == other.bytes
      end
      alias eql? ==

      def hash
        [self.class, bytes].hash
      end
    end

    class MACAddress < Address
      BROADCAST_BYTES = "\xff\xff\xff\xff\xff\xff".b.freeze

      def initialize(value)
        bytes = value.is_a?(String) && value.include?(":") ?
          value.split(":").map { |part| Integer(part, 16) }.pack("C*") : value
        super(bytes, length: 6)
      end

      def to_s
        bytes.bytes.map { |byte| format("%02x", byte) }.join(":")
      end

      def self.broadcast
        new(BROADCAST_BYTES)
      end
    end

    class IPv4Address < Address
      def initialize(value)
        bytes = value.is_a?(String) && value.include?(".") ?
          value.split(".").map { |part| Integer(part, 10) }.pack("C*") : value
        super(bytes, length: 4)
      end

      def to_s
        bytes.bytes.join(".")
      end
    end
  end
end
