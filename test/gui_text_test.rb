# frozen_string_literal: true

# Exercises GUI::Text against the real RemoteOS-SDL service: the host font is
# opened and measured for real, so this catches a face whose advance drifts
# from the 8px grid the widget code lays out on. The fallback and guard paths
# are driven through doubles because they require a host that is missing or
# lying about its fonts.

require "socket"
require "timeout"
require "rubyos"

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

root = File.expand_path("..", __dir__)
listener = TCPServer.new("127.0.0.1", 0)
port = listener.local_address.ip_port
listener.close

environment = {
  "REMOTEOS_SDL_MODE" => "headless",
  "SDL_VIDEODRIVER" => "dummy",
  "SDL_AUDIODRIVER" => "dummy"
}
bridge_pid = Process.spawn(environment,
                           ENV.fetch("REMOTEOS_SDL_BIN",
                                     File.join(root, "services", "remoteos-sdl", "remoteos-sdl")),
                           "--listen-tcp", "127.0.0.1:#{port}",
                           out: File.join(root, "build", "rubyos-gui-text-test.log"),
                           err: %i[child out])
client = nil

begin
  transport = nil
  Timeout.timeout(5) do
    loop do
      begin
        transport = RubyOS::Bridge::Transport::TCP.new(host: "127.0.0.1", port:)
        break
      rescue Errno::ECONNREFUSED
        sleep 0.02
      end
    end
  end
  client = RubyOS::Bridge::Client.new(transport)
  client.hello
  surface = RubyOS::Bridge::Surface.create(client, width: 320, height: 200)

  # --- Bitmap fallback -----------------------------------------------------
  RubyOS::GUI::Text.disable!
  assert(!RubyOS::GUI::Text.available?, "disabled renderer reports unavailable")
  assert(RubyOS::GUI::Text.advance == 8, "bitmap advance is the 8x8 cell")
  assert(RubyOS::GUI::Text.height == 8, "bitmap height is the 8x8 cell")
  assert(RubyOS::GUI::Text.draw(surface, 0, 0, "fallback") == [64, 8],
         "bitmap draw reports 8px per glyph")

  # --- Anti-aliased path ---------------------------------------------------
  enabled = RubyOS::GUI::Text.enable!(client)
  assert(enabled, "host font opened: #{RubyOS::GUI::Text.failure.inspect}")
  assert(RubyOS::GUI::Text.available?, "enabled renderer reports available")
  advance = RubyOS::GUI::Text.advance
  assert(advance.positive?, "measured advance is positive")

  # The widget code divides pixel widths by this advance, so a face that is
  # not truly fixed-pitch has to be rejected rather than laid out on a grid
  # it does not honour.
  # Differencing two runs of the same glyph cancels the ink overhang that
  # makes a lone glyph — or a run ending in one — measure wide.
  font = RubyOS::Bridge::Font.open_default(client, point_size: RubyOS::GUI::Text.point_size)
  glyph_advance = lambda do |glyph|
    short, = font.measure(glyph * 16)
    long, = font.measure(glyph * 32)
    (long - short) / 16
  end
  narrow = glyph_advance.call("i")
  wide = glyph_advance.call("W")
  assert(narrow == wide, "host face is fixed-pitch (#{narrow} vs #{wide} per glyph)")
  assert(narrow == advance, "published advance matches the measured face")
  font.close

  assert(RubyOS::GUI::Text.width("abcd") == advance * 4, "width is advance times length")
  assert(RubyOS::GUI::Text.columns_for(advance * 5) == 5, "columns_for divides by advance")
  assert(RubyOS::GUI::Text.columns_for(-10).zero?, "columns_for floors at zero")
  assert(RubyOS::GUI::Text.truncate("abcdef", advance * 3) == "abc", "truncate trims to fit")
  assert(RubyOS::GUI::Text.truncate("ab", advance * 9) == "ab", "truncate leaves short text")

  drawn_width, drawn_height = RubyOS::GUI::Text.draw(surface, 4, 4, "Ruby", color: 0xffd866)
  assert(drawn_width == advance * 4, "anti-aliased run is one advance per glyph")
  assert(drawn_height == RubyOS::GUI::Text.height, "anti-aliased run is one line tall")

  # A repeat draw must reuse the cached host surface rather than re-render.
  before = client.performance_snapshot.fetch(:guest_round_trip)["sdl.call"]&.fetch(:count) || 0
  RubyOS::GUI::Text.draw(surface, 4, 24, "Ruby", color: 0xffd866)
  after = client.performance_snapshot.fetch(:guest_round_trip)["sdl.call"]&.fetch(:count) || 0
  assert(before == after, "cached run avoided a second TTF render")

  # Multi-line text must stay interchangeable with the bitmap path, which
  # treats "\n" as a line break.
  _, multi_height = RubyOS::GUI::Text.draw(surface, 4, 48, "one\ntwo\nthree")
  assert(multi_height == RubyOS::GUI::Text.height * 3, "three lines are three rows tall")

  # --- Monospace guard -----------------------------------------------------
  # A face that bills "i" at 4px and everything else at 9px, plus a constant
  # 1px of ink overhang, is exactly the shape the differencing probe has to
  # catch: each individual run looks plausible, only the advances disagree.
  proportional = Object.new
  def proportional.measure(text)
    [text.each_char.sum { |glyph| glyph == "i" ? 4 : 9 } + 1, 17]
  end
  def proportional.close = self
  refused = begin
    RubyOS::GUI::Text.send(:measure_face, proportional)
    :accepted
  rescue RubyOS::Error => error
    error.message
  end
  assert(refused.to_s.include?("not monospace"),
         "a proportional face is refused, got #{refused.inspect}")

  # A fixed-pitch face carrying the same overhang must still be accepted, or
  # the guard above would reject every real font.
  fixed = Object.new
  def fixed.measure(text) = [text.each_char.count * 9 + 1, 17]
  def fixed.close = self
  assert(RubyOS::GUI::Text.send(:measure_face, fixed) == [9, 17],
         "overhang does not disturb a fixed-pitch measurement")

  # --- Failure is a downgrade, not a crash --------------------------------
  # A font that dies mid-session must leave the desktop drawing, not raise
  # through the compositor's redraw.
  assert(RubyOS::GUI::Text.available?, "renderer still enabled before the fault")
  RubyOS::GUI::Text.instance_variable_get(:@font).close
  drawn = RubyOS::GUI::Text.draw(surface, 0, 80, "still draws")
  assert(drawn == [88, 8], "a dead font falls back to the bitmap face, got #{drawn.inspect}")
  assert(!RubyOS::GUI::Text.available?, "a dead font disables the renderer")
  assert(RubyOS::GUI::Text.advance == 8, "advance reverts to the bitmap cell")

  surface.destroy
  RubyOS::GUI::Text.disable!
  client.call("shutdown")
  client.close
  Process.wait(bridge_pid)
  raise "bridge exited unsuccessfully" unless $?.success?

  puts "RubyOS GUI text rendering: PASS"
ensure
  if $?.nil? || !$?.respond_to?(:success?)
    begin
      client&.call("shutdown")
      client&.close
    rescue StandardError
      nil
    end
  end
  begin
    Process.kill("TERM", bridge_pid)
    Process.wait(bridge_pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
