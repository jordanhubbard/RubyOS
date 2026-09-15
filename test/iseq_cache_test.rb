# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"

root = File.expand_path("..", __dir__)
Dir.mktmpdir("rubyos-iseq-") do |directory|
  source = File.join(directory, "probe.rb")
  binary = File.join(directory, "probe.iseq")
  File.write(source, "RUBYOS_ISEQ_PROBE = 40 + 2\n")
  system(File.join(root, "build/host-ruby/bin/ruby"),
         File.join(root, "tools/freeze-iseq.rb"), source, binary) or abort
  metadata = JSON.parse(File.read("#{binary}.json"))
  abort unless metadata.fetch("engine") == "ruby"
  abort unless metadata.fetch("version") == RUBY_VERSION
  abort unless metadata.fetch("platform") == RUBY_PLATFORM
  abort unless metadata.fetch("binary_sha256") == Digest::SHA256.file(binary).hexdigest
  RubyVM::InstructionSequence.load_from_binary(File.binread(binary)).eval
  abort unless RUBYOS_ISEQ_PROBE == 42
end
puts "RubyOS exact-build ISeq cache: PASS"
