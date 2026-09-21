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
  kernel/rubyos/async.rb
  kernel/rubyos/gui/menu.rb
  kernel/rubyos/gui/file_dialog.rb
  kernel/rubyos/bridge/file_transfer.rb
  kernel/rubyos/apps/ruby_demos.rb
  kernel/rubyos/apps/graphical_demos.rb
  kernel/rubyos/apps/catalog.rb
]
missing = required - manifest
raise "embedded kernel omits: #{missing.join(', ')}" unless missing.empty?

# The embed manifest is a second, hand-maintained copy of the load order in
# kernel/rubyos.rb. Nothing forces the two to agree, so a file added to the
# library but not the manifest builds cleanly and then dies at run time in the
# guest with an uninitialized-constant error. Check the whole list, not a
# hand-picked sample, so that drift fails here instead.
#
# Two libraries are deliberately host-only and must stay out of the guest:
host_only = %w[
  kernel/rubyos/bridge/tcp.rb
  kernel/rubyos/app.rb
].freeze
libraries = File.readlines(File.join(root, "kernel", "rubyos.rb")).filter_map do |line|
  match = line.match(/^require "(rubyos(?:\/[\w\/]+)?)"/)
  "kernel/#{match[1]}.rb" if match
end
unlisted = libraries - manifest - host_only
raise "embed manifest is missing #{unlisted.join(', ')}; add them to " \
      "tools/embed-kernel.rb (or to host_only here if the guest must not " \
      "load them)" unless unlisted.empty?

# Keep the allowlist honest: an entry that later gets embedded, or dropped
# from the library, should not sit here unnoticed.
stale = host_only & manifest
raise "host-only allowlist is stale, #{stale.join(', ')} is embedded" unless stale.empty?
absent = host_only - libraries
raise "host-only allowlist names missing libraries: #{absent.join(', ')}" unless absent.empty?

puts "RubyOS embedded catalog manifest: #{libraries.length} libraries PASS"
