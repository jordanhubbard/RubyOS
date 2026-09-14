# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_network(output: $stdout)
      device = Drivers::VirtioNet.find
      stack = Net::Stack.new(device, address: "10.0.2.15", gateway: "10.0.2.2")
      output.puts "network: #{device.mac} 10.0.2.15"
      reply = stack.ping("10.0.2.2")
      RubyOS.invariant(reply, "ICMP echo reply not received")
      output.puts "network: ICMP echo reply from 10.0.2.2"
      stack
    end
  end
end
