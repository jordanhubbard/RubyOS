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
assert(RubyOS::Concurrency.stats == RubyOS::Concurrency::Stats.new(cpus: 1, online: 1,
                                                                   worker_selftests: 1),
       "hosted concurrency fallback")

input_queue = RubyOS::Input::EventQueue.new(capacity: 2)
observed_input = []
input_queue.subscribe { |event| observed_input << event.kind }
key_event = RubyOS::Input::Event.from_bridge("kind" => 1, "code" => 114, "text" => "r")
assert(key_event.is_a?(RubyOS::Input::Event) && key_event.fetch("text") == "r",
       "bridge input normalization")
assert(input_queue.post(key_event), "canonical event queue accepts input")
assert(input_queue.post(RubyOS::Input::Event.build(kind: RubyOS::Input::KEY_UP, code: 114)),
       "canonical event queue preserves releases")
assert(!input_queue.post(RubyOS::Input::Event.build(kind: RubyOS::Input::QUIT)),
       "bounded event queue rejects overflow")
assert(input_queue.dropped == 1 && observed_input == [1, 2], "input subscribers and drop metric")
assert(input_queue.poll.map(&:kind) == [1, 2] && input_queue.empty?, "ordered input polling")
ps2 = RubyOS::Input::PS2Keyboard.new
assert(ps2.feed(0x2a).nil?, "PS/2 shift modifier is state, not text")
assert(ps2.feed(0x13).text == "R", "PS/2 shifted make-code translation")
assert(ps2.feed(0x93).kind == RubyOS::Input::KEY_UP, "PS/2 break-code translation")
ps2.feed(0xaa)
assert(ps2.mods.zero?, "PS/2 modifier release")
ps2_mouse = RubyOS::Input::PS2Mouse.new(x: 10, y: 10)
mouse_events = [0x29, 5, 0xfd].flat_map { |byte| ps2_mouse.feed(byte) }
assert([mouse_events.first.dx, mouse_events.first.dy] == [5, 3], "PS/2 signed pointer motion")
assert(mouse_events.last.kind == RubyOS::Input::POINTER_DOWN && mouse_events.last.button == 1,
       "PS/2 pointer button transition")
virtio_keys = RubyOS::Input::VirtioKeyboardTranslator.new
virtio_keys.translate(1, 42, 1)
assert(virtio_keys.translate(1, 19, 1).text == "R", "VirtIO shifted EV_KEY translation")
assert(virtio_keys.translate(1, 19, 0).kind == RubyOS::Input::KEY_UP,
       "VirtIO key release translation")
virtio_keys.translate(1, 42, 0)
virtio_keys.translate(2, 0, 12)
virtio_keys.translate(2, 1, 0xffff_fffb)
pointer_event = virtio_keys.translate(0, 0, 0)
assert([pointer_event.kind, pointer_event.dx, pointer_event.dy] ==
       [RubyOS::Input::POINTER_MOVE, 12, -5], "VirtIO relative pointer translation")
assert(virtio_keys.translate(1, 0x110, 1).button == 1, "VirtIO pointer button translation")

generic_driver = Class.new do
  include RubyOS::Driver
  matches kind: :network
end
specific_driver = Class.new do
  include RubyOS::Driver
  matches kind: :network, vendor_id: 0x1af4
end
device_bus = RubyOS::Bus.new(enumerators: [lambda {
  [RubyOS::PCIDevice.new("virtio-net", vendor_id: 0x1af4, device_id: 0x1000,
                         class_code: :network,
                         resources: [RubyOS::MMIOResource.new(0x1000_1000, 0x1000),
                                     RubyOS::IRQResource.new(5)], kind: :network)]
}])
device_bus.register_driver(generic_driver, priority: 99)
device_bus.register_driver(specific_driver)
device_bus.enumerate.bind_drivers
network_device = device_bus.find_by_id(0x1af4, 0x1000).first
assert(network_device.driver.is_a?(specific_driver), "most-specific driver binding")
assert(network_device.resources.first.cover?(0x1000_1800), "typed MMIO resource range")
assert(device_bus.topology.first.include?("driver="), "device topology reporting")
removed_driver = network_device.unbind
assert(removed_driver.device.nil? && !network_device.bound?, "driver remove lifecycle")

memory = RubyOS::Memory::Manager.new(backend: RubyOS::Memory::SimulatedBackend.new(16_384))
initial_memory = memory.snapshot
frames = memory.allocate_many(2)
assert(frames.map(&:address) == [0x1000, 0x2000], "page frames have aligned addresses")
assert(memory.snapshot.used_bytes == initial_memory.used_bytes + 8_192, "page allocation metrics")
memory.release_many(frames)
assert(memory.snapshot == initial_memory, "page release restores allocator metrics")
begin
  memory.release(frames.first)
  raise "released page frame was accepted twice"
rescue RubyOS::Memory::InvalidFrame
  nil
end

small_memory = RubyOS::Memory::Manager.new(backend: RubyOS::Memory::SimulatedBackend.new(4_096))
begin
  small_memory.allocate_many(2)
  raise "out-of-memory allocation succeeded"
rescue NoMemoryError
  nil
end
assert(small_memory.snapshot.free_bytes == 4_096, "partial allocation rolls back")

fake_now = 0.0
timed = RubyOS::Scheduler.new(monotonic_ms: -> { fake_now },
                              sleeper: ->(delay) { fake_now += delay })
timed_trace = []
timed.spawn("early") { timed.sleep_for(5); timed_trace << :early }
timed.spawn("late") { timed.sleep_for(12); timed_trace << :late }
timed.run
assert(timed_trace == [:early, :late], "sleeping tasks wake in deadline order")
assert(fake_now == 12.0, "scheduler sleeps until next deadline")

lifecycle = RubyOS::Scheduler.new(monotonic_ms: -> { 0.0 }, sleeper: ->(_) {})
doomed = lifecycle.spawn("doomed") { raise "killed task ran" }
assert(lifecycle.kill(doomed.pid), "scheduler kills a ready task by PID")
assert(doomed.state == :killed && lifecycle.reap(doomed).equal?(doomed), "killed task reaping")
zombie = lifecycle.spawn("zombie") { :ruby_result }
lifecycle.spawn("request", auto_reap: true) { :short_lived }
lifecycle.run
assert(zombie.result == :ruby_result && zombie.state == :complete, "completed task result lifecycle")
assert(zombie.ticks == 1 && lifecycle.ticks == 2, "per-task CPU tick accounting")
assert(lifecycle.ps == [zombie], "short-lived task auto-reaping")
assert(lifecycle.reap(zombie.pid).equal?(zombie) && lifecycle.ps.empty?, "completed task reaping")

samples = [1_000_000_000, 1_001_500_000, 3_001_500_000, 5_001_500_000]
clock = RubyOS::Timekeeper.new(monotonic_ns: -> { samples.shift })
assert(clock.milliseconds == 1, "monotonic milliseconds")
clock.set_hms(12, 34, 56)
assert(clock.format_hms == "12:34:58", "session wall clock advances from monotonic time")

debug = RubyOS::Debug.snapshot(state.merge(memory: memory))
assert(debug.fetch(:ruby).include?("ruby"), "debug snapshot Ruby identity")
assert(debug.fetch(:memory).fetch(:total_bytes).positive?, "debug snapshot memory")
assert(debug.fetch(:concurrency).fetch(:online).positive?, "debug snapshot CPUs")
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
indexed_view = RubyOS::Chipset::View.new(4, 3, mode: RubyOS::Chipset::MODE_INDEXED)
indexed_view.palette[1] = 0x112233
indexed_view.palette[2] = 0xaabbcc
indexed_view.pf0.fill(1)
indexed_view.pf1.fill(0)
indexed_view.bplcon = RubyOS::Chipset::BPLCON_PF1_KEY
indexed_view.key_color = 0
indexed_view.pf1.put(2, 1, 2)
assert(indexed_view.pixel_at(0, 0) == 0x112233 && indexed_view.pixel_at(2, 1) == 0xaabbcc,
       "indexed dual-playfield keying")
source_field = RubyOS::Chipset::Playfield.new(2, 2, fill: 0xff)
mask_field = RubyOS::Chipset::Playfield.new(2, 2)
mask_field.put(1, 0, 1)
RubyOS::Chipset::Blitter.cookie(source_field, mask_field, indexed_view.pf0,
                                source_x: 0, source_y: 0, destination_x: 0, destination_y: 0,
                                width: 2, height: 2)
assert(indexed_view.pf0.get(1, 0) == 0xff, "cookie-cut blitter mask")
RubyOS::Chipset::Toaster.wipe_step(indexed_view, 0.5, 1.0)
assert(indexed_view.diw_stop == 1 && indexed_view.pixel_at(0, 2).zero?, "display-window wipe")
paula = RubyOS::Chipset::Paula.new
paula.channels.first.samples = [1_000, 1_000]
paula.channels.first.pan = 0
paula.channels.first.rate = 48_000
paula.channels.first.play
left, right = paula.mix(1).unpack("s<2")
assert(left == 1_000 && right.zero?, "Paula channel volume and pan")
presented = []
engine = RubyOS::Chipset::Engine.new(paula:) { |frame_bytes, audio_bytes| presented << [frame_bytes, audio_bytes] }
engine.load_view(indexed_view).start
engine.tick
engine.stop
assert(engine.ticks == 1 && presented.first.map(&:length).all?(&:positive?), "chipset clock presents raster and audio")

invaders = RubyOS::Games::Invaders.new
invaders.enemies.replace([[15, 16]])
invaders.fire.tick
assert(invaders.score == 100 && invaders.enemies.empty?, "Invaders collision and score")
assert(invaders.cue.is_a?(RubyOS::Sound::PCM), "Invaders produces Ruby PCM cues")
snake = RubyOS::Games::Snake.new
6.times { snake.tick }
assert(snake.score == 10 && snake.body.length == 4, "Snake movement, food, and growth")
snake.handle(RubyOS::Input::Event.build(kind: RubyOS::Input::KEY_DOWN, code: 115))
assert(snake.direction == [0, 1], "Snake canonical input steering")

frame = RubyOS::Bridge::Protocol.encode_json_frame('{"v":2}')
assert(RubyOS::Bridge::Protocol.decode_length(frame.byteslice(0, 4)) == 7, "bridge length")
document = { "v" => 2, "ok" => true, "values" => [nil, -3, "Ruby\nOS"] }
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

shortcut_launched = false
desktop = RubyOS::GUI::Compositor.new(width: 320, height: 240)
desktop.add_shortcut("Ruby", x: 8, y: 40) { shortcut_launched = true }
desktop.handle("kind" => 4, "button" => 1, "x" => 20, "y" => 50)
assert(shortcut_launched, "desktop shortcut launches action")
movable = desktop.add_window(RubyOS::GUI::Window.new("Move", x: 80, y: 60, width: 120, height: 90))
desktop.handle("kind" => 4, "button" => 1, "x" => 90, "y" => 70)
desktop.handle("kind" => 3, "x" => 110, "y" => 90)
desktop.handle("kind" => 5, "button" => 1, "x" => 110, "y" => 90)
assert([movable.x, movable.y] == [100, 80], "title drag moves window")
desktop.handle("kind" => 4, "button" => 1,
               "x" => movable.x + movable.width - 34, "y" => movable.y + 8)
assert(movable.minimized, "window minimize control")

editor = RubyOS::Apps::Editor.new(path: "/home/editor.txt")
editor.save("Edited by a Ruby object.\n")
assert(state.fetch(:vfs).read_file("/home/editor.txt") == "Edited by a Ruby object.\n",
       "Editor persists through VFS")

live_registry = RubyOS::Apps::Registry.new
live_runtime = RubyOS::Live::Runtime.new(vfs: state.fetch(:vfs), registry: live_registry)
first_reload = live_runtime.install("Greeter", path: "/apps/greeter.rb", source: <<~RUBY)
  class App < RubyOS::Apps::Application
    def build_window = RubyOS::GUI::Window.new("First", width: 80, height: 60)
  end
RUBY
assert(first_reload.generation == 1 && live_registry.fetch("Greeter").build_window.title == "First",
       "live runtime installs a sandboxed application class")
state.fetch(:vfs).write_file("/apps/greeter.rb", <<~RUBY)
  class App < RubyOS::Apps::Application
    def build_window = RubyOS::GUI::Window.new("Reloaded", width: 80, height: 60)
  end
RUBY
live_runtime.reload("Greeter", path: "/apps/greeter.rb")
assert(live_registry.fetch("Greeter").build_window.title == "Reloaded",
       "live runtime swaps in a freshly evaluated application")
begin
  live_runtime.install("Greeter", path: "/apps/greeter.rb", source: "class App <")
  raise "invalid live source was accepted"
rescue SyntaxError
  nil
end
assert(live_registry.fetch("Greeter").build_window.title == "Reloaded",
       "failed live compilation preserves the running application")

patch_target = Class.new { def greeting = "before" }
patches = RubyOS::Live::ClassEditor.new
patches.apply(patch_target, "def greeting = 'after'")
assert(patch_target.new.greeting == "after" && patches.history.length == 1,
       "runtime class modification applies Ruby methods")
begin
  patches.apply(patch_target, "def greeting = 'broken'; raise 'rollback'")
  raise "failing class patch was accepted"
rescue RuntimeError => error
  raise unless error.message == "rollback"
end
assert(patch_target.new.greeting == "after",
       "failing class modification restores prior methods")

graph_root = []; graph_root << { owner: graph_root }
graph = RubyOS::Introspection.object_graph(graph_root, depth: 3)
assert(graph.fetch(:nodes).length >= 2 && graph.fetch(:edges).any?,
       "bounded live object graph follows Ruby containers")
assert(RubyOS::Introspection.fibers(state.fetch(:scheduler)).all? { |row| row.key?(:fiber_id) },
       "Fiber inspection exposes scheduler identity and state")
assert(RubyOS::Introspection.drivers(state.fetch(:bus)).first.fetch(:driver).include?("SerialDriver"),
       "driver reflection exposes live device bindings")
assert(RubyOS::Introspection.class_shape(RubyOS::GUI::Button).fetch(:ancestors).include?("RubyOS::GUI::View"),
       "class reflection exposes the live view hierarchy")

http_request = RubyOS::HTTP::Parser.parse(
  "GET /ruby?mode=bare HTTP/1.1\r\nHost: rubyos\r\n\r\n"
)
assert(http_request.method == "GET" && http_request.target == "/ruby?mode=bare",
       "HTTP parser preserves method and target")
router = RubyOS::HTTP::Router.new.get("/ruby") do |environment|
  "#{environment.fetch('PATH_INFO')} #{environment.fetch('QUERY_STRING')}"
end
fake_connection = Class.new do
  attr_reader :written
  def initialize(bytes) = (@chunks = [bytes]; @written = +"")
  def read(timeout_ms:) = @chunks.shift || raise("unexpected HTTP read")
  def write(bytes) = (@written << bytes; bytes.bytesize)
  def close = self
end.new("GET /ruby?mode=bare HTTP/1.1\r\nHost: rubyos\r\n\r\n")
fake_listener = Class.new do
  def initialize(connection) = (@connection = connection)
  def accept(timeout_ms:) = @connection
end.new(fake_connection)
served = RubyOS::HTTP::Server.new(router).serve_once(fake_listener)
assert(served.fetch(:status) == 200 && fake_connection.written.include?("/ruby mode=bare"),
       "Rack-shaped HTTP server routes and responds")
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
