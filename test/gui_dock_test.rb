# frozen_string_literal: true

# Desktop geometry: dock layout, icon generation, the wallpaper ramp, and
# how window sizes follow the desktop. All pure guest-side logic -- no
# bridge, no host font -- so this runs standalone and fast.

require "rubyos"

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

Icons = RubyOS::GUI::Icons
Compositor = RubyOS::GUI::Compositor

# --- Icons ----------------------------------------------------------------

Icons.reset!
icon = Icons.for("Files")
assert(icon.width == 48 && icon.height == 48, "default icon is 48px square")
assert(Icons.for("Files").equal?(icon), "icons are memoised per name and size")

small = Icons.for("Files", size: 28)
assert(small.width == 28 && small.height == 28, "icons render at the requested size")
assert(!small.equal?(icon), "a different size is a different bitmap")

# Every declared spec must render at both dock sizes without escaping its
# bounds -- Media::Bitmap#put silently drops out-of-range pixels, so a spec
# that overflowed would quietly lose detail rather than raise.
Icons::SPECS.each do |name, spec|
  [Compositor::DOCK_ICON_COMPACT, Compositor::DOCK_ICON_SPACIOUS].each do |size|
    rendered = Icons.for(name, size:)
    assert(rendered.width == size, "#{name} renders at #{size}")
    assert(!Icons.placeholder?(name), "#{name} has a dedicated icon")
    (spec[:rects] || []).each do |x, y, width, height, _color|
      assert(x >= 0 && y >= 0 && x + width <= Icons::GRID && y + height <= Icons::GRID,
             "#{name} rect #{[x, y, width, height].inspect} fits the 48px grid")
    end
    (spec[:lines] || []).each do |x0, y0, x1, y1, _color|
      assert([x0, y0, x1, y1].all? { |v| v.between?(0, Icons::GRID) },
             "#{name} line #{[x0, y0, x1, y1].inspect} fits the 48px grid")
    end
  end
end

# A scaled rect must never collapse: the compact icon is well under half the
# grid, so naive truncation would erase the thinnest details.
tiny = Icons.for("Editor", size: Compositor::DOCK_ICON_COMPACT)
rules = (0...tiny.height).count { |y| tiny.get(9 * tiny.width / 48, y) == 0x303038 }
assert(rules.positive?, "thin rules survive scaling down to the compact icon")

# Unknown apps get a deterministic placeholder rather than nothing.
assert(Icons.placeholder?("Mandelbrot"), "an app without a spec is a placeholder")
assert(Icons.for("Mandelbrot").width == 48, "placeholders render")
assert(Icons.for("Mandelbrot").get(24, 24) == Icons.for("Mandelbrot").get(24, 24),
       "placeholder tint is stable")
tints = %w[Snake Plasma Invaders Maze].map { |name| Icons.for(name).get(24, 24) }
assert(tints.uniq.length > 1, "placeholders do not all land on one tint")

# --- Dock metrics ---------------------------------------------------------

spacious = Compositor.new(width: 1_024, height: 768)
compact = Compositor.new(width: 480, height: 300)
assert(spacious.dock_icon_size == 48 && spacious.dock_height == 72,
       "a roomy desktop gets the full 48px icon in a 72px dock")
# The label dock was 42px tall; keeping that exact height on small desktops
# means window placement and resize bounds do not shift underneath the
# visual goldens.
assert(compact.dock_icon_size == 28 && compact.dock_height == 42,
       "a compact desktop keeps the 42px dock height it always had")

# --- Slot layout and hit-testing -----------------------------------------

names = %w[Launcher Files Terminal Editor]
names.each { |name| spacious.register_dock_item(name, name[0, 5], pinned: true) { nil } }

icon_size = spacious.dock_icon_size
gap = Compositor::DOCK_ICON_GAP
span = names.length * icon_size + (names.length - 1) * gap
first_x = (1_024 - span) / 2

centers = names.map { |name| spacious.dock_item_center_by_name(name) }
centers.each_with_index do |(cx, cy), index|
  assert(cx == first_x + index * (icon_size + gap) + icon_size / 2,
         "#{names[index]} sits in the centred slot run")
  assert(cy == 768 - spacious.dock_height + spacious.dock_padding + icon_size / 2,
         "#{names[index]} is vertically centred in the dock")
end

# The whole run is centred, so the margins either side must match.
left_margin = first_x
right_margin = 1_024 - (first_x + span)
assert((left_margin - right_margin).abs <= 1, "the icon run is centred on the desktop")

dock_y = 768 - spacious.dock_height + 4
hit = ->(x) { spacious.send(:dock_item_at, x, dock_y)&.name }
assert(hit.call(centers[0][0]) == "Launcher", "a click on an icon selects it")
assert(hit.call(centers[3][0]) == "Editor", "the last slot is reachable")
# Gaps deliberately belong to neither neighbour, matching what is painted.
assert(hit.call(first_x + icon_size + gap / 2).nil?, "the gap between icons is not a hit")
assert(hit.call(first_x - 4).nil?, "empty dock left of the run is not a hit")
assert(hit.call(first_x + span + 4).nil?, "empty dock right of the run is not a hit")
assert(spacious.send(:dock_item_at, centers[0][0], 10).nil?, "the desktop is not the dock")

# --- Hover ----------------------------------------------------------------

hot = ->(x, y) do
  spacious.handle("kind" => RubyOS::Input::POINTER_MOVE, "x" => x, "y" => y)
  spacious.instance_variable_get(:@dock_hot)
end
assert(hot.call(centers[2][0], dock_y) == 2, "hovering an icon marks its slot hot")
assert(hot.call(first_x + icon_size + gap / 2, dock_y).nil?, "hovering a gap clears the hot slot")
assert(hot.call(centers[1][0], 100).nil?, "leaving the dock clears the hot slot")

# A window drag that passes over the dock must not light it up.
window = spacious.add_window(RubyOS::GUI::Window.new("Drag", x: 100, y: 100,
                                                     width: 200, height: 120))
spacious.handle("kind" => RubyOS::Input::POINTER_DOWN, "button" => 1, "x" => 120, "y" => 108)
spacious.handle("kind" => RubyOS::Input::POINTER_MOVE, "x" => centers[0][0], "y" => dock_y)
assert(spacious.instance_variable_get(:@dock_hot).nil?,
       "dragging a window over the dock leaves it cold")
spacious.handle("kind" => RubyOS::Input::POINTER_UP, "button" => 1,
                "x" => centers[0][0], "y" => dock_y)
assert(window.equal?(spacious.focused_window), "the dragged window kept focus")

# --- Wallpaper gradient ---------------------------------------------------

blend = ->(from, to, step, steps) { spacious.send(:blend, from, to, step, steps) }
assert(blend.call(0x000000, 0xffffff, 0, 4) == 0x000000, "step zero is the start colour")
assert(blend.call(0x000000, 0xffffff, 4, 4) == 0xffffff, "the last step is the end colour")
assert(blend.call(0x000000, 0xff0000, 2, 4) == 0x7f0000, "channels interpolate independently")
# Carries must not bleed between channels: 0x00ff00 halfway to 0x00ff00 is
# itself, and a green ramp must never disturb red or blue.
midpoint = blend.call(0x0000ff, 0x00ff00, 2, 4)
assert((midpoint >> 16) & 0xff == 0, "red stays clear across a green/blue ramp")
assert(blend.call(0x101010, 0x202020, 7, 0) == 0x202020, "a zero-step ramp clamps to the end")

# --- Window fit -----------------------------------------------------------

# Apps declare geometry against a 1024x768 desktop. Anything larger scales
# up; anything smaller is left alone, so the compact layouts (and the visual
# goldens taken at 480x300) are untouched.
class FixedWindowApp < RubyOS::Apps::Application
  def initialize = super(kernel: nil)

  def build_window
    window = RubyOS::GUI::Window.new("Fixed", x: 100, y: 80, width: 400, height: 300)
    @child = window.add(RubyOS::GUI::View.new(x: 0, y: 0, width: 380, height: 240),
                        anchors: %i[left right top bottom], minimum_width: 20, minimum_height: 20)
    window
  end

  attr_reader :child
end

reference = FixedWindowApp.new.tap { |app| app.launch(Compositor.new(width: 1_024, height: 768)) }
reference_window = reference.instance_variable_get(:@compositor).windows.last
assert([reference_window.width, reference_window.height] == [400, 300],
       "the reference desktop leaves declared geometry exactly as written")
assert([reference_window.x, reference_window.y] == [100, 80],
       "the reference desktop leaves declared position alone")

small = FixedWindowApp.new.tap { |app| app.launch(Compositor.new(width: 480, height: 300)) }
small_window = small.instance_variable_get(:@compositor).windows.last
assert([small_window.width, small_window.height] == [400, 300],
       "a compact desktop never shrinks a window below its declared size")

big_compositor = Compositor.new(width: 2_048, height: 1_536)
big = FixedWindowApp.new.tap { |app| app.launch(big_compositor) }
big_window = big_compositor.windows.last
assert([big_window.width, big_window.height] == [800, 600],
       "a 2x desktop doubles the window, got #{[big_window.width, big_window.height].inspect}")
assert([big_window.x, big_window.y] == [200, 160], "position scales with the window")
assert(big.child.width == 780 && big.child.height == 540,
       "anchored children follow the window, got #{[big.child.width, big.child.height].inspect}")

# Growth is capped, and bounded by the desktop the window has to live on.
huge = Compositor.new(width: 7_680, height: 4_320)
FixedWindowApp.new.launch(huge)
huge_window = huge.windows.last
assert([huge_window.width, huge_window.height] == [800, 600],
       "scaling stops at MAXIMUM_SCALE, got #{[huge_window.width, huge_window.height].inspect}")

# The limiting dimension wins, so a wide-but-short desktop does not produce
# a window taller than the screen.
wide = Compositor.new(width: 3_840, height: 1_080)
FixedWindowApp.new.launch(wide)
wide_window = wide.windows.last
assert(wide_window.height <= 1_080 - wide.dock_height,
       "a window never scales past the usable height of a short desktop")

puts "RubyOS desktop geometry, icons and window fit: PASS"
