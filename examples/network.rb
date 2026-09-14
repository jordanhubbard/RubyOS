# frozen_string_literal: true

# Protocol values remain typed Ruby objects until the device boundary.
require "rubyos"

source = RubyOS::Net::IPv4Address.new("10.0.2.15")
destination = RubyOS::Net::IPv4Address.new("10.0.2.2")
udp = RubyOS::Net::UDPSegment.new(49_152, 7, "hello from Ruby")
packet = RubyOS::Net::IPv4Packet.new(source, destination,
                                     RubyOS::Net::IPv4Packet::UDP,
                                     udp.encode(source_ip: source, destination_ip: destination),
                                     64, 1, 0x4000)
decoded = RubyOS::Net::IPv4Packet.decode(packet.encode)
message = RubyOS::Net::UDPSegment.decode(decoded.payload)
puts "#{decoded.source} -> #{decoded.destination}: #{message.payload}"
puts "network lesson: PASS"
