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
modified_key = RubyOS::Input::Event.from_bridge(
  "kind" => 1, "code" => 119, "mod" => 0x00c1
)
assert((modified_key.mods & RubyOS::Input::MOD_CTRL) != 0 &&
       (modified_key.mods & RubyOS::Input::MOD_SHIFT) != 0,
       "SDL modifier bits normalize to canonical RubyOS modifiers")
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
assert(ps2.feed(0x3b).code == RubyOS::Input::KEY_F1, "PS/2 function-key normalization")
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
assert(virtio_keys.translate(1, 59, 1).code == RubyOS::Input::KEY_F1,
       "VirtIO function-key normalization")
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

bitmap = RubyOS::Media::Bitmap.new(8, 4)
bitmap.rect(1, 1, 3, 2, color: 0x123456)
assert(bitmap.raster[10] == 0x123456, "media bitmap rectangle")
assert(bitmap.bytes.bytesize == 8 * 4 * 4, "media bitmap bytes")

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
assert(!input.handle(:click), "text input ignores window click notifications")
input_window = RubyOS::GUI::Window.new("Input", x: 20, y: 30, width: 180, height: 90)
input_window.add(input)
compositor.add_window(input_window)
assert(input_window.handle("kind" => 4, "button" => 1,
                           "x" => input_window.x + 26,
                           "y" => input_window.y + RubyOS::GUI::Window::TITLE_HEIGHT + 11) &&
       input.cursor == 1,
       "window pointer dispatch places the text caret")
input.handle("kind" => 1, "code" => 0, "text" => "uby")
input.handle("kind" => 1, "code" => 8)
input.handle("kind" => 1, "code" => 0, "text" => "y")
input.handle("kind" => 1, "code" => 13)
assert(submitted == "ruby", "text input insertion, backspace, and submit")

clipboard = RubyOS::GUI::Clipboard.new
editable = RubyOS::GUI::TextInput.new(text: "ruby blocks", width: 160, height: 24,
                                       clipboard:)
editable.focused = true
editable.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 97,
                "mods" => RubyOS::Input::MOD_CTRL)
editable.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 99,
                "mods" => RubyOS::Input::MOD_CTRL)
assert(editable.selection_range == [0, 11] && clipboard.read == "ruby blocks",
       "Ctrl+A and Ctrl+C copy a text selection to the guest clipboard")
editable.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 120,
                "mods" => RubyOS::Input::MOD_CTRL)
assert(editable.text.empty?, "Ctrl+X cuts the selected text")
editable.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 118,
                "mods" => RubyOS::Input::MOD_CTRL)
assert(editable.text == "ruby blocks", "Ctrl+V pastes guest clipboard text")
editable.move_cursor(0)
4.times do
  editable.handle("kind" => RubyOS::Input::KEY_DOWN,
                  "code" => RubyOS::GUI::TextInput::RIGHT_KEY,
                  "mods" => RubyOS::Input::MOD_SHIFT)
end
assert(editable.selected_text == "ruby", "Shift+Arrow extends a keyboard selection")

pointer_start_x = input_window.x + 10 + 4
pointer_y = input_window.y + RubyOS::GUI::Window::TITLE_HEIGHT + 9 + 4
compositor.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 1,
                  "x" => pointer_start_x, "y" => pointer_y)
compositor.handle("kind" => RubyOS::Input::POINTER_MOVE,
                  "x" => pointer_start_x + 32, "y" => pointer_y)
compositor.handle("kind" => RubyOS::Input::POINTER_UP, "button" => 1,
                  "x" => pointer_start_x + 32, "y" => pointer_y)
assert(input.selected_text == "ruby", "pointer drag selects text through window capture")

multiline = RubyOS::GUI::TextInput.new(text: "zero\none\ntwo\nthree\nfour",
                                        width: 120, height: 48, multiline: true)
multiline.focused = true
multiline.handle("kind" => RubyOS::Input::KEY_DOWN,
                 "code" => RubyOS::GUI::TextInput::UP_KEY)
assert(multiline.cursor == 17 && multiline.scroll_line == 3,
       "multiline editor moves its caret vertically and keeps it visible")
multiline.handle_pointer(12, 4, "kind" => RubyOS::Input::POINTER_DOWN)
assert(multiline.cursor == 14, "pointer placement maps visible editor rows to the text caret")
multiline.handle("kind" => RubyOS::Input::POINTER_WHEEL, "dy" => 1, "dx" => 0)
assert(multiline.scroll_line == 0, "multiline editor supports wheel scrollback")

menu_action = false
menu_bar = RubyOS::GUI::MenuBar.new(width: 320, height: 200)
menu_bar.replace([RubyOS::GUI::Menu.new(title: "RubyOS", items: [
  RubyOS::GUI::MenuItem.command("About") { menu_action = true }
])])
assert(menu_bar.handle("kind" => RubyOS::Input::POINTER_DOWN,
                       "button" => 1, "x" => 12, "y" => 8) && menu_bar.open?,
       "menu title opens its command popup")
menu_bar.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 13)
assert(menu_action && !menu_bar.open?, "keyboard activates the highlighted menu command")
compact_menu_surface = Class.new do
  attr_reader :operations
  def initialize = (@operations = [])
  def fill_rect(*arguments) = operations << [:fill_rect, *arguments]
  def draw_text(*arguments, **options) = operations << [:draw_text, *arguments, options]
end.new
compact_menus = 4.times.map do |index|
  RubyOS::GUI::Menu.new(title: "Menu#{index}", items: [])
end
menu_bar.replace(compact_menus).draw(compact_menu_surface, status: "long status value")
status_draw = compact_menu_surface.operations.reverse.find do |operation|
  operation.first == :draw_text && operation.last[:color] == 0xd8cae5
end
assert(status_draw && status_draw.fetch(3) != "long status value" &&
       status_draw.fetch(1) + status_draw.fetch(3).length * 8 <= 320,
       "compact menu bar truncates status text instead of overlapping menus")

context_launched = false
context_desktop = RubyOS::GUI::Compositor.new(width: 320, height: 240)
context_desktop.set_desktop_context_menu([
  RubyOS::GUI::MenuItem.command("Applications") { context_launched = true }
])
context_desktop.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 3,
                       "x" => 10, "y" => 170)
assert(context_desktop.context_menu_open?, "desktop right-click opens a context menu")
context_x, context_y = context_desktop.context_item_center(0)
context_desktop.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 1,
                       "x" => context_x, "y" => context_y)
assert(context_launched && !context_desktop.context_menu_open?,
       "context menu pointer activation invokes and dismisses its Ruby block")
context_window = context_desktop.add_window(
  RubyOS::GUI::Window.new("Context", x: 60, y: 50, width: 160, height: 110)
)
context_desktop.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 3,
                       "x" => 80, "y" => 90)
context_desktop.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 13)
assert(context_window.minimized, "window context menu exposes keyboard-driven controls")

context_clipboard = RubyOS::GUI::Clipboard.new.write("Ruby")
context_input = RubyOS::GUI::TextInput.new(width: 100, height: 24, clipboard: context_clipboard)
context_window = context_desktop.add_window(
  RubyOS::GUI::Window.new("Text", x: 40, y: 40, width: 150, height: 90).tap do |window|
    window.add(context_input)
  end
)
context_desktop.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 3,
                       "x" => context_window.x + 14,
                       "y" => context_window.y + RubyOS::GUI::Window::TITLE_HEIGHT + 13)
context_desktop.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 13)
assert(context_input.text == "Ruby", "text context menu enables the first available edit action")

scroll_items = 10.times.map { |index| { label: "item #{index}", kind: :file } }
scroll_list = RubyOS::GUI::ListView.new(items: scroll_items, width: 160, height: 52)
scroll_list.focused = true
assert(scroll_list.handle("kind" => RubyOS::Input::POINTER_WHEEL, "dy" => -1, "dx" => 0),
       "list view consumes wheel scrolling when more rows are available")
assert(scroll_list.scroll_offset == 3, "wheel scrolling advances the list viewport")

terminal = RubyOS::Apps::Terminal.new
terminal_window = terminal.launch(compositor)
"ruby".each_char do |character|
  compositor.handle("kind" => 1, "code" => character.ord, "text" => character)
end
compositor.handle("kind" => 1, "code" => 13, "text" => "\n")
assert(terminal.last_result.include?("Ruby is already live here"),
       "desktop Terminal routes commands through the RubyOS shell")
compositor.close(terminal_window)

files = RubyOS::Apps::Files.new
files_window = files.launch(compositor)
compositor.handle("kind" => 1, "code" => RubyOS::GUI::ListView::DOWN_KEYS.first)
compositor.handle("kind" => 1, "code" => RubyOS::GUI::ListView::DOWN_KEYS.first)
compositor.handle("kind" => 1, "code" => 13)
assert(files.path == "/home", "Files keyboard selection opens a VFS directory")
compositor.handle("kind" => 1, "code" => 8)
assert(files.path == "/", "Files Backspace navigation returns to the parent directory")
home_row_y = files_window.y + RubyOS::GUI::Window::TITLE_HEIGHT + 9 + 34 + 52 + 8
compositor.handle("kind" => 4, "button" => 1,
                  "x" => files_window.x + 24, "y" => home_row_y)
assert(files.path == "/home", "Files pointer selection opens a VFS directory")
home_file = state.fetch(:vfs).readdir("/home").reject { |entry| [".", ".."].include?(entry) }.first
files.activate_entry(label: home_file, path: "/home/#{home_file}", kind: :file)
assert(compositor.focused_window.title == "Editor - /home/#{home_file}",
       "Files opens regular files in the VFS-backed Editor")
compositor.close(compositor.focused_window)
compositor.close(files_window)

assert(RubyOS::Examples.run("enumerable_pipeline") == [1, 9, 25, 49, 81],
       "canonical Enumerable example executes from the embedded catalog")
assert(RubyOS::Examples.run("pattern_matching") == "virtio-net is ready",
       "canonical pattern matching example destructures kernel-shaped data")
assert(state.fetch(:vfs).read_file("/examples/fiber_stream.rb").include?("Fiber.yield"),
       "canonical Ruby examples are present in the live VFS")

shell_output = StringIO.new
shell = RubyOS::Shell.new(output: shell_output)
shell.execute_line("examples")
shell.execute_line("example fiber_stream")
shell.execute_line("apps")
assert(shell_output.string.include?("enumerable_pipeline") &&
       shell_output.string.include?("[1, 2, 4, 8, 16, 32]") &&
       shell_output.string.include?("Enumerable Lab"),
       "shell discovers and runs examples and lists categorized applications")

catalog = RubyOS::Apps::Catalog.build(kernel: RubyOS::Kernel)
assert(catalog.entries(category: :app).length == 11 &&
       catalog.entries(category: :demo).length == 3 &&
       catalog.entries(category: :game).length == 2,
       "application catalog preserves app, demo, and game categories")
enumerable_entry = catalog.entry("Enumerable Lab")
catalog.replace("Enumerable Lab", RubyOS::Apps::EnumerableLab.new)
assert(catalog.entry("Enumerable Lab").description == enumerable_entry.description &&
       catalog.entry("Enumerable Lab").category == :demo,
       "live replacement preserves application catalog metadata")
RubyOS::Apps::Catalog.install_desktop(compositor, catalog)
assert(compositor.pinned_dock_names == %w[Launcher Files Terminal Inspector Monitor],
       "catalog installs a compact core dock instead of pinning every application")
clock_app = catalog.fetch("Clock")
transient_clock = clock_app.launch(compositor)
assert(compositor.visible_dock_labels.include?("Clock"),
       "a running unpinned application gains a transient dock item")
compositor.minimize(transient_clock)
clock_x, clock_y = compositor.dock_item_center_by_name("Clock")
window_count = compositor.windows.length
compositor.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 1,
                  "x" => clock_x, "y" => clock_y)
assert(!transient_clock.minimized && compositor.focused_window == transient_clock &&
       compositor.windows.length == window_count,
       "dock activation restores a running window instead of duplicating it")
compositor.close(transient_clock)
assert(!compositor.visible_dock_labels.include?("Clock"),
       "closing the last unpinned application window removes its transient dock item")
monitor_x, monitor_y = compositor.dock_item_center_by_name("Monitor")
compositor.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 3,
                  "x" => monitor_x, "y" => monitor_y)
remove_x, remove_y = compositor.context_item_center(2)
compositor.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 1,
                  "x" => remove_x, "y" => remove_y)
assert(!compositor.pinned_dock_names.include?("Monitor") &&
       state.fetch(:vfs).read_file(RubyOS::Apps::DockStore::DEFAULT_PATH).start_with?(
         RubyOS::Apps::DockStore::HEADER
       ), "dock context menu persists pin removal")
dock_restore = RubyOS::GUI::Compositor.new(width: 480, height: 300)
RubyOS::Apps::Catalog.install_desktop(dock_restore, catalog)
assert(!dock_restore.pinned_dock_names.include?("Monitor"),
       "desktop installation restores the persisted dock")
dock_restore.pin_dock_item("Monitor")
assert(dock_restore.pinned_dock_names.include?("Monitor"),
       "an application can be kept in the dock again")
compositor.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => RubyOS::Input::KEY_F1,
                  "mods" => 0)
assert(compositor.focused_window.title == "Keyboard Shortcuts",
       "F1 opens the global keybinding control panel")
assert(compositor.menus.map(&:title).last == "Window",
       "focused applications contribute their own menu")
keybindings = catalog.fetch("Keybindings")
application_binding = compositor.keybindings.find { |binding| binding.name == "Applications" }
keybindings.capture(binding: application_binding)
compositor.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 97,
                  "mods" => RubyOS::Input::MOD_ALT)
rebound = compositor.keybindings.find { |binding| binding.name == "Applications" }
assert(rebound.code == 97 && rebound.mods == RubyOS::Input::MOD_ALT,
       "keybinding control panel captures and replaces a global shortcut")
compositor.rebind_key("Applications", code: RubyOS::Input::KEY_F2)
compositor.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 119,
                  "mods" => RubyOS::Input::MOD_CTRL)
assert(compositor.focused_window.title != "Keyboard Shortcuts",
       "Ctrl+W closes the focused application window")
compositor.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => RubyOS::Input::KEY_F2,
                  "mods" => 0)
assert(compositor.focused_window.title == "RubyOS Applications",
       "F2 opens the graphical application catalog")
compositor.close(compositor.focused_window)
launcher = catalog.fetch("Launcher")
launcher_window = launcher.launch(compositor)
launcher.launch_entry(entry: catalog.entry("Enumerable Lab"))
assert(compositor.focused_window.title == "Enumerable Pipeline",
       "graphical application catalog launches a Ruby demo")
compositor.close(compositor.focused_window)
compositor.close(launcher_window)

saved_keymap = state.fetch(:vfs).read_file(RubyOS::Apps::ShortcutStore::DEFAULT_PATH)
assert(saved_keymap.start_with?(RubyOS::Apps::ShortcutStore::HEADER) &&
       saved_keymap.include?("Applications\t97\t#{RubyOS::Input::MOD_ALT}"),
       "shortcut rebinding persists a versioned VFS keymap")
restored_desktop = RubyOS::GUI::Compositor.new(width: 480, height: 300)
RubyOS::Apps::Catalog.install_desktop(restored_desktop, catalog)
restored_binding = restored_desktop.keybindings.find { |binding| binding.name == "Applications" }
assert(restored_binding.code == 97 && restored_binding.mods == RubyOS::Input::MOD_ALT,
       "desktop installation restores persisted shortcut chords")
restored_desktop.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 97,
                        "mods" => RubyOS::Input::MOD_ALT)
assert(restored_desktop.focused_window.title == "RubyOS Applications",
       "restored shortcut invokes its original Ruby block")
restored_desktop.close(restored_desktop.focused_window)
keybindings.reset_defaults
default_binding = restored_desktop.keybindings.find { |binding| binding.name == "Applications" }
keymap_removed = begin
  state.fetch(:vfs).read_file(RubyOS::Apps::ShortcutStore::DEFAULT_PATH)
  false
rescue RubyOS::FS::NotFound
  true
end
assert(default_binding.code == RubyOS::Input::KEY_F2 && default_binding.mods.zero? && keymap_removed,
       "shortcut reset restores defaults and removes the persisted override")

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
stretch = movable.add(RubyOS::GUI::View.new(x: 5, y: 5, width: 90, height: 50),
                      anchors: [:left, :right, :top, :bottom],
                      minimum_width: 20, minimum_height: 20)
resize_x = movable.x + movable.width - 2
resize_y = movable.y + movable.height - 2
desktop.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 1,
               "x" => resize_x, "y" => resize_y)
desktop.handle("kind" => RubyOS::Input::POINTER_MOVE,
               "x" => resize_x + 30, "y" => resize_y + 20)
desktop.handle("kind" => RubyOS::Input::POINTER_UP, "button" => 1,
               "x" => resize_x + 30, "y" => resize_y + 20)
assert([movable.width, movable.height] == [150, 110],
       "bottom-right window resize changes its bounded geometry")
assert([stretch.width, stretch.height] == [120, 70],
       "four-edge anchors stretch child views with their window")
desktop.handle("kind" => 4, "button" => 1,
               "x" => movable.x + movable.width - 34, "y" => movable.y + 8)
assert(movable.minimized, "window minimize control")

editor = RubyOS::Apps::Editor.new(path: "/home/editor.txt")
editor.save("Edited by a Ruby object.\n")
assert(state.fetch(:vfs).read_file("/home/editor.txt") == "Edited by a Ruby object.\n",
       "Editor persists through VFS")

dialog_desktop = RubyOS::GUI::Compositor.new(width: 640, height: 480)
opened_path = nil
open_dialog = RubyOS::GUI::FileDialog.new(
  compositor: dialog_desktop, vfs: state.fetch(:vfs), mode: :open,
  path: "/home/editor.txt", extensions: [".txt"],
  on_accept: ->(path) { opened_path = path }
)
assert(open_dialog.cwd == "/home" && dialog_desktop.focused_window == open_dialog.window,
       "shared open dialog starts beside the requested path")
dialog_desktop.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 9)
dialog_desktop.handle("kind" => RubyOS::Input::KEY_DOWN, "code" => 13)
assert(opened_path == "/home/editor.txt" &&
       open_dialog.done? && !dialog_desktop.windows.include?(open_dialog.window),
       "shared open dialog keyboard action returns a VFS file and closes")
saved_path = nil
save_dialog = RubyOS::GUI::FileDialog.new(
  compositor: dialog_desktop, vfs: state.fetch(:vfs), mode: :save,
  path: "/home/new.rb", on_accept: ->(path) { saved_path = path }
)
save_dialog.filename = "renamed.rb"
assert(save_dialog.accept && saved_path == "/home/renamed.rb" && save_dialog.done?,
       "shared save dialog accepts an edited filename")

editor_window = editor.launch(dialog_desktop)
editor.open_dialog
assert(dialog_desktop.focused_window.title == "Open Ruby or text file",
       "Editor exposes the shared open dialog")
editor.file_dialog.accept("/home/editor.txt")
assert(editor.path == "/home/editor.txt" && editor_window.title.include?(editor.path),
       "Editor open workflow updates document and window identity")
editor.save_as_dialog
editor.file_dialog.filename = "editor-copy.rb"
editor.file_dialog.accept
assert(editor.path == "/home/editor-copy.rb" &&
       state.fetch(:vfs).read_file(editor.path) == editor.content,
       "Editor Save As writes the active buffer through the VFS")

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
