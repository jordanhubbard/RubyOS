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
  end
end
