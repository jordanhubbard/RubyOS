# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_network(output: $stdout)
      device = Drivers::VirtioNet.find
      lease = Net::DHCPClient.new(device).acquire
      stack = Net::Stack.new(device, address: lease.address, gateway: lease.gateway)
      output.puts "network: DHCP #{device.mac} #{lease.address} gateway #{lease.gateway}"
      reply = stack.ping(lease.gateway)
      RubyOS.invariant(reply, "ICMP echo reply not received")
      output.puts "network: ICMP echo reply from #{lease.gateway}"
      resolved = Net::DNSClient.new(stack, lease.dns).resolve("example.com")
      output.puts "network: DNS example.com -> #{resolved} via #{lease.dns}"
      echo = stack.tcp_echo(lease.gateway, 18_081, "ruby-over-tcp")
      RubyOS.invariant(echo == "echo:ruby-over-tcp", "TCP echo response did not match")
      output.puts "network: TCP echo round trip via #{lease.gateway}:18081"
      stack
    end
  end
end
