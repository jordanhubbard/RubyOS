# frozen_string_literal: true

module RubyOS
  module Net
    module Checksum
      module_function

      def internet(bytes)
        bytes = String(bytes).b
        bytes += "\0" if bytes.bytesize.odd?
        sum = bytes.unpack("n*").sum
        sum = (sum & 0xffff) + (sum >> 16) while sum > 0xffff
        (~sum) & 0xffff
      end
    end

    class EthernetFrame < Data.define(:destination, :source, :ethertype, :payload)
      IPV4 = 0x0800
      ARP = 0x0806

      def self.decode(bytes)
        bytes = String(bytes).b
        raise ArgumentError, "Ethernet frame is shorter than 14 bytes" if bytes.bytesize < 14
        new(MACAddress.new(bytes.byteslice(0, 6)), MACAddress.new(bytes.byteslice(6, 6)),
            bytes.byteslice(12, 2).unpack1("n"), bytes.byteslice(14..))
      end

      def encode
        destination.bytes + source.bytes + [ethertype].pack("n") + payload
      end
    end

    class ARPPacket < Data.define(:operation, :sender_mac, :sender_ip, :target_mac, :target_ip)
      REQUEST = 1
      REPLY = 2

      def self.decode(bytes)
        raise ArgumentError, "ARP packet is shorter than 28 bytes" if bytes.bytesize < 28
        hardware, protocol, hardware_length, protocol_length, operation = bytes.unpack("nnCCn")
        raise ArgumentError, "unsupported ARP address format" unless hardware == 1 && protocol == EthernetFrame::IPV4 && hardware_length == 6 && protocol_length == 4
        new(operation, MACAddress.new(bytes.byteslice(8, 6)), IPv4Address.new(bytes.byteslice(14, 4)),
            MACAddress.new(bytes.byteslice(18, 6)), IPv4Address.new(bytes.byteslice(24, 4)))
      end

      def encode
        [1, EthernetFrame::IPV4, 6, 4, operation].pack("nnCCn") +
          sender_mac.bytes + sender_ip.bytes + target_mac.bytes + target_ip.bytes
      end

      def ethernet_frame
        destination = operation == REQUEST ? MACAddress.broadcast : target_mac
        EthernetFrame.new(destination, sender_mac, EthernetFrame::ARP, encode)
      end
    end

    class IPv4Packet < Data.define(:source, :destination, :protocol, :payload, :ttl, :identification, :flags)
      ICMP = 1
      TCP = 6
      UDP = 17

      def self.decode(bytes)
        bytes = String(bytes).b
        raise ArgumentError, "IPv4 packet is shorter than 20 bytes" if bytes.bytesize < 20
        version = bytes.getbyte(0) >> 4
        header_length = (bytes.getbyte(0) & 0x0f) * 4
        total_length = bytes.byteslice(2, 2).unpack1("n")
        raise ArgumentError, "invalid IPv4 header" unless version == 4 && header_length >= 20 && total_length >= header_length && total_length <= bytes.bytesize
        raise ArgumentError, "bad IPv4 header checksum" unless Checksum.internet(bytes.byteslice(0, header_length)).zero?
        new(IPv4Address.new(bytes.byteslice(12, 4)), IPv4Address.new(bytes.byteslice(16, 4)),
            bytes.getbyte(9), bytes.byteslice(header_length, total_length - header_length),
            bytes.getbyte(8), bytes.byteslice(4, 2).unpack1("n"),
            bytes.byteslice(6, 2).unpack1("n"))
      end

      def encode
        header = [0x45, 0, 20 + payload.bytesize, identification, flags, ttl,
                  protocol, 0].pack("CCnnnCCn") + source.bytes + destination.bytes
        header[10, 2] = [Checksum.internet(header)].pack("n")
        header + payload
      end
    end

    class UDPSegment < Data.define(:source_port, :destination_port, :payload)
      def self.decode(bytes)
        raise ArgumentError, "UDP datagram is shorter than 8 bytes" if bytes.bytesize < 8
        source, destination, length, = bytes.unpack("nnnn")
        raise ArgumentError, "invalid UDP length" unless length >= 8 && length <= bytes.bytesize
        new(source, destination, bytes.byteslice(8, length - 8))
      end

      def encode(source_ip:, destination_ip:)
        length = 8 + payload.bytesize
        header = [source_port, destination_port, length, 0].pack("nnnn")
        pseudo = source_ip.bytes + destination_ip.bytes + [0, IPv4Packet::UDP, length].pack("CCn")
        checksum = Checksum.internet(pseudo + header + payload)
        checksum = 0xffff if checksum.zero?
        header[6, 2] = [checksum].pack("n")
        header + payload
      end
    end

    class ICMPPacket < Data.define(:type, :code, :identifier, :sequence, :payload)
      ECHO_REPLY = 0
      ECHO_REQUEST = 8

      def self.decode(bytes)
        raise ArgumentError, "ICMP packet is shorter than 8 bytes" if bytes.bytesize < 8
        raise ArgumentError, "bad ICMP checksum" unless Checksum.internet(bytes).zero?
        type, code, _, identifier, sequence = bytes.unpack("CCnnn")
        new(type, code, identifier, sequence, bytes.byteslice(8..))
      end

      def encode
        bytes = [type, code, 0, identifier, sequence].pack("CCnnn") + payload
        bytes[2, 2] = [Checksum.internet(bytes)].pack("n")
        bytes
      end

      def echo_reply
        raise Error, "not an ICMP echo request" unless type == ECHO_REQUEST
        self.class.new(ECHO_REPLY, 0, identifier, sequence, payload)
      end
    end
  end
end
