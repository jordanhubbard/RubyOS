# frozen_string_literal: true

require "socket"

module RubyOS
  module Bridge
    module Transport
      class TCP
        def initialize(host:, port:)
          @socket = TCPSocket.new(host, port)
          @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        end

        def write(bytes)
          bytes = String(bytes).b
          offset = 0
          offset += @socket.write(bytes.byteslice(offset..)) while offset < bytes.bytesize
          self
        end

        def read_exact(length)
          bytes = +"".b
          bytes << @socket.readpartial(length - bytes.bytesize) while bytes.bytesize < length
          bytes
        rescue EOFError
          raise Error.new(-1, "display host closed the transport")
        end

        def close
          @socket.close unless @socket.closed?
        end
      end
    end
  end
end
