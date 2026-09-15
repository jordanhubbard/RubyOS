#!/usr/bin/env ruby
# frozen_string_literal: true

# Build a deliberately local ISeq cache. The manifest is part of the contract:
# consumers must reject it unless engine, version, revision, platform, source
# digest, and binary digest all match the running VM.
require "digest"
require "json"

source_path, output_path = ARGV
abort "usage: freeze-iseq.rb SOURCE OUTPUT" unless source_path && output_path

source = File.binread(source_path)
iseq = RubyVM::InstructionSequence.compile(source, source_path, source_path, 1)
metadata = {
  format: "rubyos-iseq-cache-v1",
  engine: RUBY_ENGINE,
  version: RUBY_VERSION,
  revision: defined?(RUBY_REVISION) ? RUBY_REVISION : nil,
  platform: RUBY_PLATFORM,
  source_sha256: Digest::SHA256.hexdigest(source)
}
binary = iseq.to_binary(JSON.generate(metadata))
metadata[:binary_sha256] = Digest::SHA256.hexdigest(binary)

File.binwrite(output_path, binary)
File.write("#{output_path}.json", JSON.pretty_generate(metadata) + "\n")
loaded_metadata = JSON.parse(
  RubyVM::InstructionSequence.load_from_binary_extra_data(binary),
  symbolize_names: true
)
abort "ISeq metadata round trip failed" unless loaded_metadata == metadata.except(:binary_sha256)
RubyVM::InstructionSequence.load_from_binary(binary)
puts "#{output_path}: #{binary.bytesize} bytes for #{RUBY_DESCRIPTION}"
