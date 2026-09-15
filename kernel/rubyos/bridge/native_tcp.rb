# frozen_string_literal: true

module RubyOS
  module Bridge
    module Transport
      # Adapts RubyOS::Net::TCPConnection to the byte-stream contract used by
      # the RemoteOS client. The network driver has 2 KiB DMA buffers, so writes
      # are deliberately segmented below Ethernet MTU instead of constructing
      # oversized IP packets.
      class NativeTCP
        MAX_SEGMENT = 1_400

        def initialize(connection, timeout_ms: 30_000)
          @connection = connection
          @timeout_ms = Integer(timeout_ms)
          @pending = +"".b
        end

        def write(bytes)
          bytes = String(bytes).b
          offset = 0
          while offset < bytes.bytesize
            chunk = bytes.byteslice(offset, MAX_SEGMENT)
            @connection.write(chunk)
            offset += chunk.bytesize
          end
          self
        end

        def read_exact(length)
          length = Integer(length)
          raise ArgumentError, "negative read length" if length.negative?
          while @pending.bytesize < length
            @pending << @connection.read(timeout_ms: @timeout_ms)
          end
          result = @pending.byteslice(0, length)
          @pending = @pending.byteslice(length..) || +"".b
          result
        end

        def close
          @connection.close if @connection.respond_to?(:close)
          self
        end
      end
    end
  end
end
