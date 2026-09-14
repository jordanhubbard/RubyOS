# frozen_string_literal: true

module RubyOS
  module Bridge
    class Error < RubyOS::Error
      attr_reader :code

      def initialize(code, message)
        @code = code
        super("bridge error #{code}: #{message}")
      end
    end

    class Client
      attr_reader :features

      def initialize(transport)
        @transport = transport
        @next_id = 1
        @features = [].freeze
      end

      def hello
        result = call("hello", { protocol: PROTOCOL_VERSION })
        RubyOS.invariant(result.fetch("protocol") == PROTOCOL_VERSION,
                         "display protocol mismatch")
        @features = result.fetch("features", []).freeze
        result
      end

      def call(operation, parameters = {}, payload: +"".b)
        id = @next_id
        @next_id += 1
        parameters = parameters.transform_keys(&:to_s)
        parameters["payload_len"] = payload.bytesize unless payload.empty?
        json = Codec.dump(v: PROTOCOL_VERSION, id:, op: operation,
                          params: parameters)
        @transport.write(Protocol.encode_json_frame(json, payload))

        length = Protocol.decode_length(@transport.read_exact(4))
        response = Codec.load(@transport.read_exact(length))
        RubyOS.invariant(response.fetch("id") == id, "bridge response id mismatch")
        unless response["ok"]
          failure = response.fetch("error", {})
          raise Error.new(failure.fetch("code", -1),
                          failure.fetch("msg", "unknown display failure"))
        end
        response.fetch("result", {})
      end

      def sdl_call(name, *arguments)
        call("sdl.call", { name: String(name), args: arguments })
      end

      def close
        @transport.close
      end
    end
  end
end
