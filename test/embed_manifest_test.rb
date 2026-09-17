# frozen_string_literal: true

require "rbconfig"

root = File.expand_path("..", __dir__)
manifest = IO.popen(
  { "RUBYOS_EMBED_LIST" => "1" },
  [RbConfig.ruby, File.join(root, "tools", "embed-kernel.rb")],
  &:read
).lines.map(&:strip)

required = %w[
  kernel/rubyos/examples.rb
  kernel/rubyos/apps/ruby_demos.rb
  kernel/rubyos/apps/catalog.rb
]
missing = required - manifest
raise "embedded kernel omits: #{missing.join(', ')}" unless missing.empty?

puts "RubyOS embedded catalog manifest: PASS"
