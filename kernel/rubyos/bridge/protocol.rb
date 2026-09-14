# frozen_string_literal: true

module RubyOS
  module Bridge
    PROTOCOL_VERSION = 1
    MAX_FRAME = 16 * 1024 * 1024

    Request = Data.define(:id, :operation, :parameters, :payload)

    module Protocol
      module_function

      def encode_json_frame(json, payload = +"")
        json = String(json).b
        payload = String(payload).b
        RubyOS.invariant(json.bytesize.between?(1, MAX_FRAME), "invalid JSON frame size")
        [json.bytesize].pack("N") << json << payload
      end

      def decode_length(header)
        RubyOS.invariant(header.bytesize == 4, "bridge header must be four bytes")
        length = header.unpack1("N")
        RubyOS.invariant(length.between?(1, MAX_FRAME), "invalid bridge frame size")
        length
      end
    end
  end
end

