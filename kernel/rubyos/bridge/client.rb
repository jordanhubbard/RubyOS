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
        @metrics = {}
        @pending = []
        @hello_result = nil
        @batch_limit = 256
      end

      def hello
        return @hello_result if @hello_result
        result = call("hello", { protocol: PROTOCOL_VERSION, client: "rubyos" })
        RubyOS.invariant(result.fetch("protocol") == PROTOCOL_VERSION,
                         "display protocol mismatch")
        @features = result.fetch("features", []).freeze
        @batch_limit = [Integer(result.fetch("limits", {}).fetch("batch_ops", 256)), 256].min
        RubyOS.invariant(@batch_limit.positive?, "invalid batch limit")
        @hello_result = result.freeze
      end

      def call(operation, parameters = {}, payload: +"".b)
        flush unless @pending.empty?
        send_call(operation, parameters, payload:)
      end

      def cast(operation, parameters = {})
        flush if @pending.length >= @batch_limit
        @pending << { "op" => String(operation),
                      "params" => parameters.transform_keys(&:to_s) }
        self
      end

      def flush
        return self if @pending.empty?
        operations = @pending
        @pending = []
        result = send_call("render.batch", { ops: operations })
        raise Error.new(9, "render batch contained failed operations") unless result.fetch("errors", 0).zero?
        self
      end

      def send_call(operation, parameters = {}, payload: +"".b)
        started_ns = monotonic_ns
        id = @next_id
        @next_id += 1
        parameters = parameters.transform_keys(&:to_s)
        parameters["payload_len"] = payload.bytesize unless payload.empty?
        json = Codec.dump(v: PROTOCOL_VERSION, id:, op: operation,
                          params: parameters)
        @transport.write(Protocol.encode_json_frame(json, payload))

        length = Protocol.decode_length(@transport.read_exact(4))
        response = Codec.load(@transport.read_exact(length))
        RubyOS.invariant(response.fetch("v") == PROTOCOL_VERSION,
                         "bridge response protocol mismatch")
        RubyOS.invariant(response.fetch("id") == id, "bridge response id mismatch")
        unless response["ok"]
          failure = response.fetch("error", {})
          raise Error.new(failure.fetch("code", -1),
                          failure.fetch("msg", "unknown display failure"))
        end
        response.fetch("result", {})
      ensure
        record_metric(operation, monotonic_ns - started_ns) if started_ns
      end

      def metrics(reset: false)
        snapshot = @metrics.transform_values do |row|
          count = row.fetch(:count)
          {
            count:,
            total_ns: row.fetch(:total_ns),
            max_ns: row.fetch(:max_ns),
            mean_us: count.zero? ? 0.0 : row.fetch(:total_ns) / count / 1_000.0,
            max_us: row.fetch(:max_ns) / 1_000.0
          }.freeze
        end.freeze
        @metrics.clear if reset
        snapshot
      end

      def notify(operation, parameters = {})
        flush
        json = Codec.dump(v: PROTOCOL_VERSION, id: 0, op: operation, params: parameters)
        @transport.write(Protocol.encode_json_frame(json, +"".b))
        self
      end

      def performance_snapshot(reset: false)
        host = call("telemetry.snapshot", { reset: })
        { guest_round_trip: metrics(reset:), host_service: host }.freeze
      end

      def sdl_call(name, *arguments)
        call("sdl.call", { name: String(name), args: arguments })
      end

      def close
        flush
      ensure
        @transport.close
      end

      private

      def monotonic_ns
        if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:monotonic_ns)
          RubyOS::HAL.monotonic_ns
        else
          Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        end
      end

      def record_metric(operation, elapsed_ns)
        row = (@metrics[String(operation)] ||= { count: 0, total_ns: 0, max_ns: 0 })
        row[:count] += 1
        row[:total_ns] += elapsed_ns
        row[:max_ns] = elapsed_ns if elapsed_ns > row[:max_ns]
      end
    end
  end
end
