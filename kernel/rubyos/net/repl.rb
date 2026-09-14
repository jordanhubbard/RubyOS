# frozen_string_literal: true

module RubyOS
  module Net
    class REPLServer
      Session = Struct.new(:remote_ip, :remote_mac, :remote_port, :sequence,
                           :acknowledgment, :context, :evaluations,
                           keyword_init: true)

      attr_reader :port

      def initialize(stack, port: 17_011, context: TOPLEVEL_BINDING)
        @listener = stack.listen(port)
        @stack = stack
        @port = port
        @context = context
        @sessions = {}
      end

      def serve_once(timeout_ms: 10_000)
        connection = @listener.accept(timeout_ms:)
        source = connection.read(timeout_ms:)
        response = begin
          "=> #{eval(source, @context).inspect}\n"
        rescue Exception => error
          "#{error.class}: #{error.message}\n"
        end
        connection.write(response)
        response
      end

      def serve_many(response_count:, timeout_ms: 15_000)
        completed = 0
        deadline = RubyOS::HAL.monotonic_ns + timeout_ms * 1_000_000
        while completed < response_count && RubyOS::HAL.monotonic_ns < deadline
          tuple = @stack.wait_for_tcp_frame(timeout_ms: 10) { true }
          next unless tuple
          ethernet, ip, segment = tuple
          next unless segment.destination_port == port
          key = [ip.source, segment.source_port]
          if (segment.flags & TCPSegment::SYN) != 0 && (segment.flags & TCPSegment::ACK).zero?
            accept_syn(key, ethernet, ip, segment)
            next
          end
          session = @sessions[key]
          next unless session
          if (segment.flags & TCPSegment::FIN) != 0
            session.acknowledgment = (segment.sequence + 1) & 0xffffffff
            transmit(session, TCPSegment::ACK, +"".b)
            @sessions.delete(key)
            next
          end
          next if segment.payload.empty?
          next unless segment.sequence == session.acknowledgment
          session.acknowledgment = (segment.sequence + segment.payload.bytesize) & 0xffffffff
          response = evaluate(segment.payload, session.context)
          transmit(session, TCPSegment::PSH | TCPSegment::ACK, response)
          session.sequence = (session.sequence + response.bytesize) & 0xffffffff
          session.evaluations += 1
          completed += 1
        end
        raise Error, "TCP REPL service timed out after #{completed}/#{response_count} evaluations" if completed < response_count
        { sessions: @sessions.length, evaluations: completed }
      end

      private

      def accept_syn(key, ethernet, ip, segment)
        sequence = (0x5255_4259 + @sessions.length * 0x1000) & 0xffffffff
        session = Session.new(remote_ip: ip.source, remote_mac: ethernet.source,
                              remote_port: segment.source_port,
                              sequence: (sequence + 1) & 0xffffffff,
                              acknowledgment: (segment.sequence + 1) & 0xffffffff,
                              context: Object.new.instance_eval { binding }, evaluations: 0)
        @sessions[key] = session
        syn_ack = TCPSegment.new(port, session.remote_port, sequence, session.acknowledgment,
                                 TCPSegment::SYN | TCPSegment::ACK, 65_535, +"".b)
        @stack.transmit_tcp(session.remote_ip, session.remote_mac, syn_ack)
      end

      def transmit(session, flags, payload)
        segment = TCPSegment.new(port, session.remote_port, session.sequence,
                                 session.acknowledgment, flags, 65_535, payload)
        @stack.transmit_tcp(session.remote_ip, session.remote_mac, segment)
      end

      def evaluate(source, context)
        "=> #{eval(source, context).inspect}\n"
      rescue Exception => error
        "#{error.class}: #{error.message}\n"
      end
    end
  end
end
