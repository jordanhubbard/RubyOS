# frozen_string_literal: true

require "stringio"
require "rubyos"
require_relative "../kernel/boot"

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

output = StringIO.new
state = RubyOS::Kernel.boot(output:)

assert(output.string.include?("Ruby owns the machine"), "boot marker")
assert(state[:trace] == [[0, :start], [1, :start], [0, :finish], [1, :finish]], "fiber order")
assert(state[:scheduler].tasks.all? { |task| task.state == :complete }, "task completion")
assert(state[:timer_trace] == [:sleep, :wake], "bare scheduler deadline")

fake_now = 0.0
timed = RubyOS::Scheduler.new(monotonic_ms: -> { fake_now },
                              sleeper: ->(delay) { fake_now += delay })
timed_trace = []
timed.spawn("early") { timed.sleep_for(5); timed_trace << :early }
timed.spawn("late") { timed.sleep_for(12); timed_trace << :late }
timed.run
assert(timed_trace == [:early, :late], "sleeping tasks wake in deadline order")
assert(fake_now == 12.0, "scheduler sleeps until next deadline")

samples = [1_000_000_000, 1_001_500_000, 3_001_500_000, 5_001_500_000]
clock = RubyOS::Timekeeper.new(monotonic_ns: -> { samples.shift })
assert(clock.milliseconds == 1, "monotonic milliseconds")
clock.set_hms(12, 34, 56)
assert(clock.format_hms == "12:34:58", "session wall clock advances from monotonic time")
clock.clear_wall_clock
assert(!clock.wall_clock_set?, "session wall clock clears")

quiet = RubyOS::Sound::PCM.new([20_000, -20_000])
loud = RubyOS::Sound::PCM.new([20_000, -20_000])
mixed = RubyOS::Sound::Mixer.new.mix(quiet, loud)
assert(mixed.samples == [32_767, -32_768], "PCM mixer saturates int16")
tone = RubyOS::Sound::Waveform.sine(440, duration_ms: 10)
assert(tone.frames == 480 && tone.stereo_bytes.bytesize == 1_920, "sine waveform PCM shape")

playfield = RubyOS::Chipset::Playfield.new(8, 4)
RubyOS::Chipset::Blitter.fill(playfield, x: 1, y: 1, width: 3, height: 2, color: 0x123456)
assert(playfield.get(2, 2) == 0x123456, "chipset blitter fill")
RubyOS::Chipset::Blitter.copy(playfield, playfield, source_x: 1, source_y: 1,
                              destination_x: 4, destination_y: 1, width: 3, height: 2)
assert(playfield.get(5, 2) == 0x123456, "overlap-safe chipset blitter copy")
chipset_view = RubyOS::Apps::ChipsetWorkbench.new.build_view
assert(chipset_view.raster.length == 512, "chipset raster dimensions")
assert(chipset_view.pixel_at(23, 7) == 0xffd866, "chipset sprite priority")

frame = RubyOS::Bridge::Protocol.encode_json_frame('{"v":1}')
assert(RubyOS::Bridge::Protocol.decode_length(frame.byteslice(0, 4)) == 7, "bridge length")
document = { "v" => 1, "ok" => true, "values" => [nil, -3, "Ruby\nOS"] }
assert(RubyOS::Bridge::Codec.load(RubyOS::Bridge::Codec.dump(document)) == document,
       "pure Ruby bridge JSON round trip")

button_clicked = false
button = RubyOS::GUI::Button.new("Run", action: ->(_) { button_clicked = true })
assert(button.handle(:click), "button consumes click")
assert(button_clicked, "button action")

surface = Class.new do
  attr_reader :operations
  def initialize = (@operations = [])
  def fill_rect(*arguments) = operations << [:fill_rect, *arguments]
  def draw_text(*arguments, **options) = operations << [:draw_text, *arguments, options]
end.new
compositor = RubyOS::GUI::Compositor.new(width: 480, height: 300)
first_window = RubyOS::GUI::Window.new("First", x: 20, y: 30, width: 180, height: 120)
second_window = RubyOS::GUI::Window.new("Second", x: 80, y: 60, width: 180, height: 120)
compositor.add_window(first_window)
compositor.add_window(second_window)
assert(compositor.focused_window == second_window, "new window receives focus")
assert(compositor.window_at(100, 90) == second_window, "hit testing follows z-order")
compositor.focus(first_window)
assert(compositor.focused_window == first_window, "window focus raises z-order")
compositor.draw(surface, uptime: "42 ms")
assert(surface.operations.any? { |operation| operation.include?("First") }, "window chrome rendering")
compositor.handle("kind" => 4, "button" => 1,
                  "x" => first_window.x + first_window.width - 12, "y" => first_window.y + 10)
assert(!compositor.windows.include?(first_window), "window close hit target")

submitted = nil
input = RubyOS::GUI::TextInput.new(text: "r", width: 120, height: 24,
                                    on_submit: ->(text) { submitted = text })
input.handle("kind" => 1, "code" => 0, "text" => "uby")
input.handle("kind" => 1, "code" => 8)
input.handle("kind" => 1, "code" => 0, "text" => "y")
input.handle("kind" => 1, "code" => 13)
assert(submitted == "ruby", "text input insertion, backspace, and submit")

settings = RubyOS::Apps::Settings.new
settings_window = settings.launch(compositor)
compositor.handle("kind" => 4, "button" => 1,
                  "x" => settings_window.x + 16,
                  "y" => settings_window.y + RubyOS::GUI::Window::TITLE_HEIGHT + 50)
assert(!settings.animations, "window click dispatch reaches Settings button")

editor = RubyOS::Apps::Editor.new(path: "/home/editor.txt")
editor.save("Edited by a Ruby object.\n")
assert(state.fetch(:vfs).read_file("/home/editor.txt") == "Edited by a Ruby object.\n",
       "Editor persists through VFS")
viewer = RubyOS::Apps::ImageViewer.new
assert(viewer.launch(compositor).title == "Image Viewer", "Image Viewer launches a window")

shell_input = ["1 + 2\n", "version\n", "exit\n"]
shell_output = StringIO.new
RubyOS::Shell.new(input: -> { shell_input.shift }, output: shell_output).run
assert(shell_output.string.include?("=> 3"), "shell evaluates Ruby")
assert(shell_output.string.include?(RUBY_VERSION), "shell version command")

vfs = state.fetch(:vfs)
assert(vfs.readdir("/").include?("home"), "tmpfs seeded directory")
assert(vfs.read_file("/home/welcome.txt").start_with?("Welcome to RubyOS"), "tmpfs seeded file")
vfs.mkdir("/var")
vfs.write_file("/var/state", "ruby")
descriptor = vfs.open("/var/state", RubyOS::FS::OpenFlags::READ_WRITE)
assert(vfs.read(descriptor, 2) == "ru", "descriptor read")
assert(vfs.seek(descriptor, -1, :end) == 3, "descriptor seek")
assert(vfs.write(descriptor, "y") == 1, "descriptor write")
vfs.close(descriptor)
assert(vfs.read_file("/var/state") == "ruby", "descriptor content")
vfs.open("/var/state", RubyOS::FS::OpenFlags::WRITE_ONLY).tap do |write_only|
  begin
    vfs.read(write_only, 1)
    raise "write-only descriptor was readable"
  rescue RubyOS::FS::PermissionDenied
    nil
  ensure
    vfs.close(write_only)
  end
end
mounted = RubyOS::FS::TmpFS.new.seed("inside" => "mounted")
vfs.mount("/var/mount", mounted)
assert(vfs.read_file("/var/mount/inside") == "mounted", "longest-prefix mount routing")
assert(vfs.readdir("/var").include?("mount"), "mount visible in parent directory")
vfs.unlink("/var/state")
begin
  vfs.stat("/var/state")
  raise "unlinked file remained visible"
rescue RubyOS::FS::NotFound
  nil
end

puts "RubyOS kernel exploration: PASS"
