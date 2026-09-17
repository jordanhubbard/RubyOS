# frozen_string_literal: true

require "digest"
require "fileutils"

module RubyOSVisualGolden
  FORMAT = "rubyos-tilehash-v1"
  TILE = 16
  MAX_DIFFS = 40
  module_function

  def bitmap(path)
    bytes = File.binread(path)
    raise "#{path}: not a BMP" unless bytes.start_with?("BM") && bytes.bytesize >= 54

    offset = bytes.unpack1("@10V")
    width = bytes.unpack1("@18l<")
    signed_height = bytes.unpack1("@22l<")
    bits = bytes.unpack1("@28v")
    compression = bytes.unpack1("@30V")
    raise "#{path}: invalid dimensions" unless width.positive? && !signed_height.zero?
    raise "#{path}: unsupported #{bits}-bit compressed BMP" unless [24, 32].include?(bits) && compression.zero?

    height = signed_height.abs
    bytes_per_pixel = bits / 8
    stride = ((width * bits + 31) / 32) * 4
    expected = offset + stride * height
    raise "#{path}: truncated pixel data" if bytes.bytesize < expected

    rows = Array.new(height) do |display_y|
      stored_y = signed_height.positive? ? height - display_y - 1 : display_y
      start = offset + stored_y * stride
      bytes.byteslice(start, width * bytes_per_pixel)
    end
    [width, height, bits, rows]
  end

  def tile_hashes(path, tile: TILE)
    width, height, bits, rows = bitmap(path)
    bytes_per_pixel = bits / 8
    hashes = []
    (0...height).step(tile) do |top|
      (0...width).step(tile) do |left|
        digest = Digest::SHA256.new
        [tile, height - top].min.times do |row_offset|
          row = rows.fetch(top + row_offset)
          digest << row.byteslice(left * bytes_per_pixel,
                                  [tile, width - left].min * bytes_per_pixel)
        end
        hashes << digest.hexdigest
      end
    end
    [width, height, hashes]
  end

  def golden_text(width, height, hashes)
    (["#{FORMAT} width=#{width} height=#{height} tile=#{TILE}"] + hashes).join("\n") + "\n"
  end

  def read_golden(path, width, height)
    lines = File.readlines(path, chomp: true)
    header = "#{FORMAT} width=#{width} height=#{height} tile=#{TILE}"
    raise "#{path}: incompatible header #{lines.first.inspect}" unless lines.shift == header

    lines.reject(&:empty?)
  end

  def identifier(path, extension)
    File.basename(path, extension)
  end

  def display_name(identifier)
    identifier.delete_prefix("rubyos-app-").delete_prefix("rubyos-interaction-")
  end

  def run(architecture, capture_directory, root: File.expand_path("..", __dir__))
    architecture = String(architecture)
    raise "unsupported architecture: #{architecture}" unless %w[arm64 x86_64].include?(architecture)

    app_captures = Dir[File.join(capture_directory, "rubyos-app-*.bmp")].sort
    interaction_captures = Dir[File.join(capture_directory,
                                         "rubyos-interaction-*.bmp")].sort
    captures = app_captures + interaction_captures
    raise "no visual captures found in #{capture_directory}" if captures.empty?
    interaction_ids = interaction_captures.map { |path| identifier(path, ".bmp") }
    required_interactions = %w[rubyos-interaction-file-drag rubyos-interaction-media-wipe]
    missing_interactions = required_interactions - interaction_ids
    unless missing_interactions.empty?
      raise "interaction captures are missing: #{missing_interactions.join(', ')}"
    end

    golden_directory = File.join(root, "test", "goldens", architecture)
    refresh = ENV["RUBYOS_GOLDEN_REFRESH"] == "1"
    FileUtils.mkdir_p(golden_directory) if refresh
    goldens = Dir[File.join(golden_directory, "*.tilehashes")].sort
    capture_ids = captures.map { |path| identifier(path, ".bmp") }.sort
    golden_ids = goldens.map { |path| identifier(path, ".tilehashes") }.sort

    unless refresh || capture_ids == golden_ids
      missing = capture_ids - golden_ids
      stale = golden_ids - capture_ids
      raise "golden catalog mismatch: missing=#{missing.inspect} stale=#{stale.inspect}"
    end

    results = captures.map do |capture|
      id = identifier(capture, ".bmp")
      name = display_name(id)
      golden = File.join(golden_directory, "#{id}.tilehashes")
      width, height, actual = tile_hashes(capture)
      if refresh
        File.write(golden, golden_text(width, height, actual))
        puts "REFRESH #{architecture}/#{name}: #{actual.length} tiles"
        [name, 0]
      else
        expected = read_golden(golden, width, height)
        raise "#{name}: tile count changed #{expected.length} -> #{actual.length}" unless expected.length == actual.length

        differences = actual.zip(expected).count { |left, right| left != right }
        puts "#{differences <= MAX_DIFFS ? 'PASS' : 'FAIL'} #{architecture}/#{name}: " \
             "#{differences}/#{actual.length} tiles differ (max #{MAX_DIFFS})"
        [name, differences]
      end
    end

    if refresh
      stale_paths = goldens.reject do |path|
        capture_ids.include?(identifier(path, ".tilehashes"))
      end
      stale_paths.each { |path| File.delete(path) }
    end
    failures = results.select { |_name, differences| differences > MAX_DIFFS }
    raise "visual golden failures: #{failures.map(&:first).join(', ')}" unless failures.empty?

    puts "RubyOS #{architecture} visual goldens: #{results.length} PASS"
    true
  end
end

if $PROGRAM_NAME == __FILE__
  RubyOSVisualGolden.run(ARGV.fetch(0), ARGV.fetch(1))
end
