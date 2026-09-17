# frozen_string_literal: true

require "tmpdir"
require "stringio"
require_relative "visual_golden_test"

def bmp24(width, height)
  stride = ((width * 3 + 3) / 4) * 4
  pixels = "\0".b * (stride * height)
  file_size = 54 + pixels.bytesize
  header = "BM".b + [file_size, 0, 0, 54].pack("VvvV")
  dib = [40, width, height, 1, 24, 0, pixels.bytesize,
         2_835, 2_835, 0, 0].pack("VllvvVVllVV")
  header + dib + pixels
end

Dir.mktmpdir("rubyos-visual-golden-") do |directory|
  capture = File.join(directory, "rubyos-app-probe.bmp")
  interaction = File.join(directory, "rubyos-interaction-file-drag.bmp")
  File.binwrite(capture, bmp24(656, 16))
  File.binwrite(interaction, bmp24(656, 16))
  root = File.join(directory, "root")

  previous = ENV["RUBYOS_GOLDEN_REFRESH"]
  begin
    ENV["RUBYOS_GOLDEN_REFRESH"] = "1"
    RubyOSVisualGolden.run("arm64", directory, root:)
    ENV["RUBYOS_GOLDEN_REFRESH"] = "0"
    RubyOSVisualGolden.run("arm64", directory, root:)

    changed = File.binread(capture)
    (0...656).step(RubyOSVisualGolden::TILE) do |x|
      changed.setbyte(54 + x * 3, 0xff)
    end
    File.binwrite(capture, changed)
    original_stdout = $stdout
    begin
      $stdout = StringIO.new
      begin
        RubyOSVisualGolden.run("arm64", directory, root:)
        raise "visual comparison accepted more than the mismatch threshold"
      rescue RuntimeError => error
        raise unless error.message.include?("visual golden failures: probe")
      end
    ensure
      $stdout = original_stdout
    end
  ensure
    ENV["RUBYOS_GOLDEN_REFRESH"] = previous
  end
end

puts "RubyOS visual golden parser, refresh, and regression threshold: PASS"
