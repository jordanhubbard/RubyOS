# frozen_string_literal: true

# RubyOS keeps these examples in the kernel image and mounts their source at
# /examples. This host-side lesson proves the same catalog remains executable.
require "rubyos"

expected = {
  "enumerable_pipeline" => [1, 9, 25, 49, 81],
  "pattern_matching" => "virtio-net is ready",
  "fiber_stream" => [1, 2, 4, 8, 16, 32],
  "mixin_protocol" => ["anonymous", 42]
}
expected.each do |name, value|
  result = RubyOS::Examples.run(name)
  raise "#{name} returned #{result.inspect}" unless result == value
end

puts "ruby_language lesson: #{RubyOS::Examples::LESSONS.length} canonical examples"
puts "ruby_language lesson: PASS"
