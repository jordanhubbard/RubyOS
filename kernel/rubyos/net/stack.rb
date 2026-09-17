# frozen_string_literal: true

module RubyOS
  module Net
    class Stack
      attr_reader :device, :address, :gateway

      def initialize(device, address:, gateway:)
        @device = device
        @address = address.is_a?(IPv4Address) ? address : IPv4Address.new(address)
        @gateway = gateway.is_a?(IPv4Address) ? gateway : IPv4Address.new(gateway)
        @arp = {}
        @identification = 0
      end

      def ping(destination, timeout_ms: 3_000)
        destination = IPv4Address.new(destination) unless destination.is_a?(IPv4Address)
        next_hop = destination
        mac = resolve(next_hop, timeout_ms:)
        request = ICMPPacket.new(ICMPPacket::ECHO_REQUEST, 0, 0x5255, 1, "RubyOS ping")
        packet = IPv4Packet.new(address, destination, IPv4Packet::ICMP,
                                request.encode, 64, next_identification, 0x4000)
        device.send(EthernetFrame.new(mac, device.mac, EthernetFrame::IPV4, packet.encode).encode)
        wait_for(timeout_ms) do |frame|
          next unless frame.ethertype == EthernetFrame::IPV4
          ip = IPv4Packet.decode(frame.payload)
          next unless ip.protocol == IPv4Packet::ICMP && ip.source == destination
          icmp = ICMPPacket.decode(ip.payload)
          icmp if icmp.type == ICMPPacket::ECHO_REPLY && icmp.identifier == request.identifier
        end
      end

      def tcp_echo(destination, port, payload, timeout_ms: 5_000)
        connection = connect(destination, port, timeout_ms:)
        connection.write(payload)
        connection.read(timeout_ms:)
      ensure
        connection&.close
      end

      def connect(destination, port, timeout_ms: 5_000)
        destination = IPv4Address.new(destination) unless destination.is_a?(IPv4Address)
        remote_mac = resolve(destination, timeout_ms:)
        local_port = next_local_port
        sequence = 0x5255_4259 ^ local_port
        syn = TCPSegment.new(local_port, Integer(port), sequence, 0,
                             TCPSegment::SYN, 65_535, +"".b)
        transmit_tcp(destination, remote_mac, syn)

        frame = wait_for_tcp_frame(timeout_ms:) do |_ethernet, ip, segment|
          ip.source == destination && segment.source_port == Integer(port) &&
            segment.destination_port == local_port
        end
        raise Error, "TCP handshake timed out" unless frame
        _, _, syn_ack = frame
        raise Error, "TCP peer rejected connection" if (syn_ack.flags & TCPSegment::RST) != 0
        expected = TCPSegment::SYN | TCPSegment::ACK
        raise Error, "invalid TCP handshake flags" unless (syn_ack.flags & expected) == expected
        raise Error, "invalid TCP handshake acknowledgment" unless syn_ack.acknowledgment == ((sequence + 1) & 0xffffffff)

        connection = TCPConnection.new(self, remote_ip: destination, remote_mac:,
                                       remote_port: Integer(port), local_port:,
                                       sequence: (sequence + 1) & 0xffffffff,
                                       acknowledgment: (syn_ack.sequence + 1) & 0xffffffff)
        connection.acknowledge
        connection
      end

      def udp_exchange(destination, port, payload, source_port:, timeout_ms: 5_000)
        destination = IPv4Address.new(destination) unless destination.is_a?(IPv4Address)
        remote_mac = resolve(destination, timeout_ms:)
        segment = UDPSegment.new(source_port, port, String(payload).b)
        send_ip(destination, remote_mac, IPv4Packet::UDP,
                segment.encode(source_ip: address, destination_ip: destination))
        deadline = RubyOS::HAL.monotonic_ns + timeout_ms * 1_000_000
        while RubyOS::HAL.monotonic_ns < deadline
          bytes = device.receive
          next unless bytes
          frame = EthernetFrame.decode(bytes)
          next unless frame.ethertype == EthernetFrame::IPV4
          packet = IPv4Packet.decode(frame.payload)
          next unless packet.protocol == IPv4Packet::UDP && packet.source == destination
          reply = UDPSegment.decode(packet.payload)
          return reply.payload if reply.destination_port == source_port && reply.source_port == port
        end
        raise Error, "UDP request to #{destination}:#{port} timed out"
      end

      def listen(port)
        TCPListener.new(self, Integer(port))
      end

      def transmit_tcp(destination, remote_mac, segment)
        send_ip(destination, remote_mac, IPv4Packet::TCP,
                segment.encode(source_ip: address, destination_ip: destination))
      end

      def wait_for_tcp_frame(timeout_ms:)
        deadline = RubyOS::HAL.monotonic_ns + timeout_ms * 1_000_000
        while RubyOS::HAL.monotonic_ns < deadline
          bytes = device.receive
          next unless bytes
          frame = EthernetFrame.decode(bytes)
          next unless frame.ethertype == EthernetFrame::IPV4
          packet = IPv4Packet.decode(frame.payload)
          next unless packet.protocol == IPv4Packet::TCP
          segment = TCPSegment.decode(packet.payload, source_ip: packet.source,
                                      destination_ip: packet.destination)
          tuple = [frame, packet, segment]
          return tuple if yield(*tuple)
        end
        nil
      end

      def resolve(ip, timeout_ms: 3_000)
        return @arp.fetch(ip) if @arp.key?(ip)
        zero = MACAddress.new("\0".b * 6)
        request = ARPPacket.new(ARPPacket::REQUEST, device.mac, address, zero, ip)
        device.send(request.ethernet_frame.encode)
        result = wait_for(timeout_ms) do |frame|
          next unless frame.ethertype == EthernetFrame::ARP
          packet = ARPPacket.decode(frame.payload)
          learn(packet.sender_ip, packet.sender_mac)
          packet.sender_mac if packet.operation == ARPPacket::REPLY && packet.sender_ip == ip
        end
        raise Error, "ARP timeout for #{ip}" unless result
        result
      end

      def learn(ip, mac)
        @arp[ip] = mac
      end

      private

      def send_ip(destination, remote_mac, protocol, payload)
        packet = IPv4Packet.new(address, destination, protocol, payload,
                                64, next_identification, 0x4000)
        device.send(EthernetFrame.new(remote_mac, device.mac, EthernetFrame::IPV4,
                                      packet.encode).encode)
      end

      def wait_for_tcp(source, local_port, remote_port, timeout_ms)
        deadline = RubyOS::HAL.monotonic_ns + timeout_ms * 1_000_000
        while RubyOS::HAL.monotonic_ns < deadline
          segment = receive_tcp(source, local_port, remote_port)
          return segment if segment
        end
        nil
      end

      def receive_tcp(source, local_port, remote_port)
        bytes = device.receive
        return nil unless bytes
        frame = EthernetFrame.decode(bytes)
        return nil unless frame.ethertype == EthernetFrame::IPV4
        packet = IPv4Packet.decode(frame.payload)
        return nil unless packet.protocol == IPv4Packet::TCP && packet.source == source
        segment = TCPSegment.decode(packet.payload, source_ip: packet.source,
                                    destination_ip: packet.destination)
        return nil unless segment.destination_port == local_port && segment.source_port == remote_port
        segment
      end

      def next_identification
        @identification = (@identification + 1) & 0xffff
      end

      def next_local_port
        @local_port = ((@local_port || 49_151) + 1)
        @local_port = 49_152 if @local_port > 65_535
        @local_port
      end

      def wait_for(timeout_ms)
        deadline = RubyOS::HAL.monotonic_ns + timeout_ms * 1_000_000
        while RubyOS::HAL.monotonic_ns < deadline
          bytes = device.receive
          next unless bytes
          frame = EthernetFrame.decode(bytes)
          result = yield(frame)
          return result if result
        end
        nil
      end
    end
  end
end
