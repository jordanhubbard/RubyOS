# frozen_string_literal: true

module RubyOS
  module Net
    class TCPSegment < Data.define(:source_port, :destination_port, :sequence, :acknowledgment,
                                   :flags, :window, :payload)
      FIN = 0x01
      SYN = 0x02
      RST = 0x04
      PSH = 0x08
      ACK = 0x10

      def self.decode(bytes, source_ip:, destination_ip:)
        raise ArgumentError, "TCP segment is shorter than 20 bytes" if bytes.bytesize < 20
        source_port, destination_port, sequence, acknowledgment,
          offset_flags, window, = bytes.unpack("nnNNnnnn")
        header_length = (offset_flags >> 12) * 4
        raise ArgumentError, "invalid TCP header length" unless header_length >= 20 && header_length <= bytes.bytesize
        pseudo = source_ip.bytes + destination_ip.bytes + [0, IPv4Packet::TCP, bytes.bytesize].pack("CCn")
        raise ArgumentError, "bad TCP checksum" unless Checksum.internet(pseudo + bytes).zero?
        new(source_port, destination_port, sequence, acknowledgment,
            offset_flags & 0x1ff, window, bytes.byteslice(header_length..))
      end

      def encode(source_ip:, destination_ip:)
        header = [source_port, destination_port, sequence, acknowledgment,
                  (5 << 12) | flags, window, 0, 0].pack("nnNNnnnn")
        pseudo = source_ip.bytes + destination_ip.bytes +
                 [0, IPv4Packet::TCP, header.bytesize + payload.bytesize].pack("CCn")
        header[16, 2] = [Checksum.internet(pseudo + header + payload)].pack("n")
        header + payload
      end
    end

    class TCPConnection
      attr_reader :remote_ip, :remote_port, :local_port

      def initialize(stack, remote_ip:, remote_mac:, remote_port:, local_port:,
                     sequence:, acknowledgment:)
        @stack = stack
        @remote_ip = remote_ip
        @remote_mac = remote_mac
        @remote_port = remote_port
        @local_port = local_port
        @sequence = sequence
        @acknowledgment = acknowledgment
      end

      def read(timeout_ms: 10_000)
        frame = @stack.wait_for_tcp_frame(timeout_ms:) do |_ethernet, ip, segment|
          ip.source == remote_ip && segment.source_port == remote_port &&
            segment.destination_port == local_port && !segment.payload.empty?
        end
        raise Error, "TCP receive timed out" unless frame
        _, _, segment = frame
        @acknowledgment = (segment.sequence + segment.payload.bytesize) & 0xffffffff
        transmit(TCPSegment::ACK, +"".b)
        segment.payload
      end

      def write(payload)
        payload = String(payload).b
        transmit(TCPSegment::PSH | TCPSegment::ACK, payload)
        @sequence = (@sequence + payload.bytesize) & 0xffffffff
        payload.bytesize
      end

      private

      def transmit(flags, payload)
        segment = TCPSegment.new(local_port, remote_port, @sequence, @acknowledgment,
                                 flags, 65_535, payload)
        @stack.transmit_tcp(remote_ip, @remote_mac, segment)
      end
    end

    class TCPListener
      attr_reader :port

      def initialize(stack, port)
        @stack = stack
        @port = port
        @sequence = 0x5255_4259
      end

      def accept(timeout_ms: 10_000)
        incoming = @stack.wait_for_tcp_frame(timeout_ms:) do |_ethernet, _ip, segment|
          segment.destination_port == port && (segment.flags & TCPSegment::SYN) != 0 &&
            (segment.flags & TCPSegment::ACK).zero?
        end
        raise Error, "TCP accept timed out on port #{port}" unless incoming
        ethernet, ip, syn = incoming
        acknowledgment = (syn.sequence + 1) & 0xffffffff
        syn_ack = TCPSegment.new(port, syn.source_port, @sequence, acknowledgment,
                                 TCPSegment::SYN | TCPSegment::ACK, 65_535, +"".b)
        @stack.transmit_tcp(ip.source, ethernet.source, syn_ack)

        established = @stack.wait_for_tcp_frame(timeout_ms:) do |_frame, packet, segment|
          packet.source == ip.source && segment.source_port == syn.source_port &&
            segment.destination_port == port && (segment.flags & TCPSegment::ACK) != 0 &&
            segment.acknowledgment == ((@sequence + 1) & 0xffffffff)
        end
        raise Error, "TCP handshake timed out on port #{port}" unless established
        TCPConnection.new(@stack, remote_ip: ip.source, remote_mac: ethernet.source,
                          remote_port: syn.source_port, local_port: port,
                          sequence: (@sequence + 1) & 0xffffffff,
                          acknowledgment:)
      end
    end
  end
end
