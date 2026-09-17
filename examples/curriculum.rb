# frozen_string_literal: true

# The same immutable catalog is mounted into the guest at /examples. This host
# runner executes every frozen lesson so additions cannot become documentation-
# only examples that fail at the RubyOS prompt.
require "rubyos"

results = RubyOS::Examples.each.to_h do |lesson|
  selector = "#{lesson.track}/#{lesson.name}"
  [selector, RubyOS::Examples.run(selector)]
end

raise "start-here primes failed" unless results.fetch("start_here/prime_enumerator").last == 47
raise "Fiber mailbox failed" unless results.fetch("concurrency/fiber_mailbox") ==
                                    %w[message-1 message-2 message-3]
raise "VFS lesson failed" unless results.dig("storage/vfs_round_trip", :remaining).empty?
raise "packet lesson failed" unless results.dig("networking/packet_round_trip", :body) ==
                                    "hello from Ruby"

puts "curriculum lesson: #{RubyOS::Examples.tracks.length} tracks, #{results.length} runnable lessons"
puts "curriculum lesson: PASS"
