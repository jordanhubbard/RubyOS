# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_web(port: 8_080)
      device = Drivers::VirtioNet.find
      lease = Net::DHCPClient.new(device).acquire
      stack = Net::Stack.new(device, address: lease.address, gateway: lease.gateway)
      router = HTTP::Router.new
        .get("/") { "RubyOS Rack-shaped server on CRuby #{RUBY_VERSION}\n" }
        .get("/objects") do
          leaders = Introspection.heap_summary(limit: 5)
          [200, { "content-type" => "text/plain" },
           leaders.map { |name, count| "#{name}: #{count}\n" }]
        end
      RubyOS::HAL.serial_write("[RubyOS] HTTP ready on #{lease.address}:#{port}\n")
      result = HTTP::Server.new(router).serve_once(stack.listen(port), timeout_ms: 120_000)
      RubyOS.invariant(result.fetch(:status) == 200, "HTTP response status")
      RubyOS::HAL.serial_write("[RubyOS] Rack-shaped HTTP server: PASS\n")
      true
    end
  end
end
