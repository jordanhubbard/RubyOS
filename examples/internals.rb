# frozen_string_literal: true

# Drivers advertise Ruby predicates; Fibers supply explicit kernel tasks.
require "rubyos"

bus = RubyOS::Bus.new
console = bus.add(RubyOS::Device.new("lesson-console", kind: :serial, port: 0x3f8))
bus.bind([RubyOS::SerialDriver])
scheduler = RubyOS::Scheduler.new
trace = []
2.times do |index|
  scheduler.spawn("lesson-#{index}") { trace << index; scheduler.yield_now; trace << -index }
end
scheduler.run
puts "internals lesson: #{console.driver.class}, Fiber trace #{trace.inspect}"
puts "internals lesson: PASS"
