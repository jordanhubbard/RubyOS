# frozen_string_literal: true

require "rubyos"

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

source_mac = RubyOS::Net::MACAddress.new("02:00:00:00:00:01")
destination_mac = RubyOS::Net::MACAddress.new("ff:ff:ff:ff:ff:ff")
source_ip = RubyOS::Net::IPv4Address.new("10.0.2.15")
destination_ip = RubyOS::Net::IPv4Address.new("10.0.2.2")
assert(source_mac.to_s == "02:00:00:00:00:01", "MAC address formatting")
assert(source_ip.to_s == "10.0.2.15", "IPv4 address formatting")

arp = RubyOS::Net::ARPPacket.new(RubyOS::Net::ARPPacket::REQUEST, source_mac, source_ip,
                                 destination_mac, destination_ip)
frame = RubyOS::Net::EthernetFrame.decode(arp.ethernet_frame.encode)
decoded_arp = RubyOS::Net::ARPPacket.decode(frame.payload)
assert(frame.ethertype == RubyOS::Net::EthernetFrame::ARP, "ARP EtherType")
assert(decoded_arp.sender_ip == source_ip, "ARP sender round trip")

icmp = RubyOS::Net::ICMPPacket.new(RubyOS::Net::ICMPPacket::ECHO_REQUEST, 0, 7, 11, "ruby-ping")
decoded_icmp = RubyOS::Net::ICMPPacket.decode(icmp.encode)
assert(decoded_icmp.echo_reply.type == RubyOS::Net::ICMPPacket::ECHO_REPLY, "ICMP echo reply")

udp = RubyOS::Net::UDPSegment.new(12_345, 53, "ruby-dns")
udp_bytes = udp.encode(source_ip:, destination_ip:)
decoded_udp = RubyOS::Net::UDPSegment.decode(udp_bytes)
assert(decoded_udp.payload == "ruby-dns", "UDP payload round trip")
pseudo = source_ip.bytes + destination_ip.bytes + [0, RubyOS::Net::IPv4Packet::UDP,
                                                    udp_bytes.bytesize].pack("CCn")
assert(RubyOS::Net::Checksum.internet(pseudo + udp_bytes).zero?, "UDP checksum")

ip = RubyOS::Net::IPv4Packet.new(source_ip, destination_ip, RubyOS::Net::IPv4Packet::UDP,
                                 udp_bytes, 64, 42, 0x4000)
decoded_ip = RubyOS::Net::IPv4Packet.decode(ip.encode)
assert(decoded_ip.source == source_ip, "IPv4 source round trip")
assert(decoded_ip.identification == 42, "IPv4 identification round trip")
assert(RubyOS::Net::UDPSegment.decode(decoded_ip.payload).destination_port == 53,
       "IPv4 UDP demultiplexing")

tcp = RubyOS::Net::TCPSegment.new(49_152, 443, 123, 456,
                                  RubyOS::Net::TCPSegment::PSH | RubyOS::Net::TCPSegment::ACK,
                                  32_768, "ruby-stream")
tcp_bytes = tcp.encode(source_ip:, destination_ip:)
decoded_tcp = RubyOS::Net::TCPSegment.decode(tcp_bytes, source_ip:, destination_ip:)
assert(decoded_tcp.sequence == 123, "TCP sequence round trip")
assert(decoded_tcp.payload == "ruby-stream", "TCP payload round trip")

dhcp = RubyOS::Net::DHCPMessage.new(transaction: 0x12345678, client_mac: source_mac,
                                    options: { 53 => [RubyOS::Net::DHCPMessage::DISCOVER].pack("C") })
wire = dhcp.encode.dup
wire.setbyte(0, 2)
wire[16, 4] = source_ip.bytes
decoded_dhcp = RubyOS::Net::DHCPMessage.decode(wire)
assert(decoded_dhcp.transaction == 0x12345678, "DHCP transaction round trip")
assert(decoded_dhcp.message_type == RubyOS::Net::DHCPMessage::DISCOVER, "DHCP option decoding")

puts "RubyOS network packets: PASS"
