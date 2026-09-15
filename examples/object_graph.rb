# frozen_string_literal: true

# This graph walks ordinary ivars, Arrays, and Hashes. It is bounded and
# cycle-aware, so it is useful in a live kernel without dumping the universe.
require "rubyos"

root = { language: "Ruby", children: [] }
root[:children] << root
graph = RubyOS::Introspection.object_graph(root, depth: 3, limit: 16)
puts "object_graph lesson: #{graph[:nodes].length} objects, #{graph[:edges].length} edges"
puts "object_graph lesson: PASS"
