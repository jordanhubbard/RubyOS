# frozen_string_literal: true

module RubyOS
  module Net
    class Stack
      attr_reader :device, :address, :gateway

      def initialize(device, address:, gateway:)
        @device = device
        @address = IPv4Address.new(address)
        @gateway = IPv4Address.new(gateway)
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

      def next_identification
        @identification = (@identification + 1) & 0xffff
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
