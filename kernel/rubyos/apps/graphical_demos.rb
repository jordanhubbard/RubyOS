# frozen_string_literal: true

module RubyOS
  module Apps
    class DemoCanvas < GUI::View
      attr_reader :bitmap, :scale

      def initialize(bitmap:, scale: 1, on_key: nil, on_event: nil, on_pointer: nil, **options)
        @bitmap = bitmap
        @scale = Integer(scale)
        raise ArgumentError, "canvas scale must be positive" unless @scale.positive?

        @on_key = on_key
        @on_event = on_event
        @on_pointer = on_pointer
        @pointer_captured = false
        super(width: bitmap.width * @scale, height: bitmap.height * @scale, **options)
      end

      def draw(surface)
        super
        surface.draw_bitmap(x, y, bitmap, scale:)
      end

      def handle(event)
        return false unless focused

        kind = event.fetch("kind", 0)
        if @on_event && [Input::KEY_DOWN, Input::KEY_UP].include?(kind)
          return !!@on_event.call(event)
        end
        return false unless kind == Input::KEY_DOWN && @on_key

        !!@on_key.call(event)
      end

      def handle_pointer(local_x, local_y, event)
        kind = event.fetch("kind", Input::POINTER_DOWN)
        return false if kind == Input::POINTER_DOWN && !contains?(local_x, local_y)
        return false if kind != Input::POINTER_DOWN && !pointer_capture?

        @pointer_captured = true if kind == Input::POINTER_DOWN
        point_x = [[(local_x - x) / scale, 0].max, bitmap.width - 1].min
        point_y = [[(local_y - y) / scale, 0].max, bitmap.height - 1].min
        handled = @on_pointer ? @on_pointer.call(kind, point_x, point_y, event) : false
        @pointer_captured = false if kind == Input::POINTER_UP
        invalidate if handled
        !!handled
      end

      def focusable? = true
      def pointer_capture? = @pointer_captured
    end

    class GraphicalDemo < Application
      BITMAP_WIDTH = 160
      BITMAP_HEIGHT = 72
      SCALE = 2

      attr_reader :bitmap, :canvas

      private

      def build_demo_window(title, instructions:, scale: SCALE,
                            on_key: nil, on_event: nil, on_pointer: nil, &tick)
        window_x, window_y = spacious_desktop? ? [148, 72] : [66, 30]
        @window = GUI::Window.new(title, x: window_x, y: window_y,
                                  width: 344, height: 222, resizable: false,
                                  background: 0x111827)
        @canvas = @window.add(DemoCanvas.new(
          bitmap: @bitmap, scale:, x: 0, y: 0,
          on_key:, on_event:, on_pointer:
        ))
        @status = @window.add(GUI::Label.new(instructions, x: 0, y: 150,
                                              width: 320, color: 0xa8d8ff))
        @window.focus_child(@canvas)
        @window.on_tick(&tick) if tick
        @window
      end

      def show_status(text)
        @status.text = String(text) if @status
        @status&.invalidate
      end
    end

    class LifeDemo < GraphicalDemo
      GRID_WIDTH = 40
      GRID_HEIGHT = 18
      NEIGHBORS = [-1, 0, 1].product([-1, 0, 1]).reject { |dx, dy| dx.zero? && dy.zero? }.freeze

      attr_reader :generation, :cells

      def initialize(**options)
        super
        @seed = 0
        reset
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT, background: 0x081018)
        render
        build_demo_window(
          "Life with Hash#tally", instructions: "Space pause | S step | R seed | C clear",
          on_key: method(:handle_key), on_pointer: method(:handle_pointer)
        ) { tick }
      end

      def step(*)
        counts = cells.keys.flat_map do |x, y|
          NEIGHBORS.map { |dx, dy| [(x + dx) % GRID_WIDTH, (y + dy) % GRID_HEIGHT] }
        end.tally
        @cells = counts.each_with_object({}) do |(cell, neighbors), next_cells|
          next_cells[cell] = true if neighbors == 3 || (neighbors == 2 && cells.key?(cell))
        end
        @generation += 1
        render
        true
      end
      alias advance step

      def toggle_pause(*)
        @paused = !@paused
        update_status
        true
      end

      def reset(*)
        @seed += 1
        random = Random.new(0x52554259 + @seed)
        @cells = GRID_WIDTH.times.flat_map do |x|
          GRID_HEIGHT.times.filter_map { |y| [x, y] if random.rand < 0.22 }
        end.to_h { |cell| [cell, true] }
        @generation = 0
        @paused = false
        @tick_count = 0
        render if @bitmap
        true
      end

      def clear(*)
        @cells = {}
        @generation = 0
        @paused = true
        render
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Life", items: [
          GUI::MenuItem.command("Pause / Resume", shortcut: "Space") { toggle_pause },
          GUI::MenuItem.command("Step", shortcut: "S") { step },
          GUI::MenuItem.command("Reseed", shortcut: "R") { reset },
          GUI::MenuItem.command("Clear", shortcut: "C") { clear }
        ]), *super]
      end

      private

      def tick
        @tick_count += 1
        step if !@paused && (@tick_count % 8).zero?
      end

      def handle_key(event)
        case event.fetch("code", 0)
        when 32 then toggle_pause
        when 115, 83 then step
        when 114, 82 then reset
        when 99, 67 then clear
        else false
        end
      end

      def handle_pointer(kind, x, y, _event)
        return false unless kind == Input::POINTER_DOWN

        cell = [x / 4, y / 4]
        cells.key?(cell) ? cells.delete(cell) : cells[cell] = true
        @paused = true
        render
        true
      end

      def render
        @bitmap.clear(0x081018)
        cells.each_key do |x, y|
          color = ((x + y + generation) % 4).zero? ? 0xffd866 : 0x51d6c5
          @bitmap.rect(x * 4, y * 4, 3, 3, color:)
        end
        update_status
      end

      def update_status
        show_status("Gen #{generation} | #{cells.length} cells | #{@paused ? 'PAUSED' : 'RUNNING'}")
      end
    end

    class MandelbrotDemo < GraphicalDemo
      BITMAP_WIDTH = 64
      BITMAP_HEIGHT = 32
      SCALE = 4
      PALETTES = [
        [0x21182f, 0x553184, 0x8f7cff, 0x51d6c5, 0xffd866, 0xff668a],
        [0x081018, 0x184e77, 0x1e6091, 0x34a0a4, 0x76c893, 0xd9ed92],
        [0x180b2c, 0x5c1a6f, 0xa83279, 0xe95d74, 0xf6bd60, 0xf7ede2]
      ].map(&:freeze).freeze

      attr_reader :center, :span

      def initialize(**options)
        super
        @palette_index = 0
        reset
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT)
        render
        build_demo_window(
          "Complex Plane", instructions: "Click zoom | R reset | C palette",
          scale: SCALE,
          on_key: method(:handle_key), on_pointer: method(:handle_pointer)
        )
      end

      def zoom_at(x, y)
        aspect = BITMAP_HEIGHT.fdiv(BITMAP_WIDTH)
        @center = Complex(
          center.real + (x.fdiv(BITMAP_WIDTH) - 0.5) * span,
          center.imag + (y.fdiv(BITMAP_HEIGHT) - 0.5) * span * aspect
        )
        @span *= 0.5
        render
        true
      end

      def reset(*)
        @center = Complex(-0.5, 0.0)
        @span = 3.2
        render if @bitmap
        true
      end

      def cycle_palette(*)
        @palette_index = (@palette_index + 1) % PALETTES.length
        render
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Fractal", items: [
          GUI::MenuItem.command("Reset", shortcut: "R") { reset },
          GUI::MenuItem.command("Cycle palette", shortcut: "C") { cycle_palette }
        ]), *super]
      end

      private

      def handle_key(event)
        case event.fetch("code", 0)
        when 114, 82 then reset
        when 99, 67 then cycle_palette
        else false
        end
      end

      def handle_pointer(kind, x, y, _event)
        kind == Input::POINTER_DOWN ? zoom_at(x, y) : false
      end

      def render
        palette = PALETTES.fetch(@palette_index)
        aspect = BITMAP_HEIGHT.fdiv(BITMAP_WIDTH)
        BITMAP_HEIGHT.times do |y|
          imaginary = center.imag + (y.fdiv(BITMAP_HEIGHT) - 0.5) * span * aspect
          BITMAP_WIDTH.times do |x|
            point = Complex(center.real + (x.fdiv(BITMAP_WIDTH) - 0.5) * span, imaginary)
            real = 0.0
            imaginary_value = 0.0
            escaped = nil
            18.times do |iteration|
              next_real = real * real - imaginary_value * imaginary_value + point.real
              imaginary_value = 2.0 * real * imaginary_value + point.imag
              real = next_real
              if real * real + imaginary_value * imaginary_value > 4.0
                escaped = iteration
                break
              end
            end
            color = escaped ? palette.fetch(escaped % palette.length) : 0x050509
            @bitmap.put(x, y, color)
          end
        end
        show_status("center #{format('%+.3f', center.real)} #{format('%+.3f', center.imag)}i | span #{format('%.3f', span)}")
      end
    end

    class SpirographDemo < GraphicalDemo
      CURVES = [[29.0, 11.0, 18.0], [31.0, 17.0, 13.0], [27.0, 8.0, 20.0]].freeze
      COLORS = [0x51d6c5, 0x8f7cff, 0xff668a, 0xffd866].freeze

      attr_reader :curve_index

      def initialize(**options)
        super
        @curve_index = 0
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT, background: 0x090712)
        render
        build_demo_window("Ruby Spirograph", instructions: "N next curve | R redraw",
                          on_key: method(:handle_key))
      end

      def next_curve(*)
        @curve_index = (curve_index + 1) % CURVES.length
        render
        true
      end
      alias advance next_curve

      def redraw(*)
        render
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Curve", items: [
          GUI::MenuItem.command("Next", shortcut: "N") { next_curve },
          GUI::MenuItem.command("Redraw", shortcut: "R") { redraw }
        ]), *super]
      end

      private

      def handle_key(event)
        case event.fetch("code", 0)
        when 110, 78 then next_curve
        when 114, 82 then redraw
        else false
        end
      end

      def render
        @bitmap.clear(0x090712)
        outer, inner, pen = CURVES.fetch(curve_index)
        turn = Math::PI * 2.0
        points = (0...180).map do |step|
          raw_angle = step * Math::PI / 30
          angle = raw_angle % turn
          ratio = (outer - inner) / inner
          pen_angle = (ratio * raw_angle) % turn
          x = (outer - inner) * Math.cos(angle) + pen * Math.cos(pen_angle)
          y = (outer - inner) * Math.sin(angle) - pen * Math.sin(pen_angle)
          [80 + x.round, 36 + (y * 0.72).round]
        end
        points.each_with_index do |(x1, y1), index|
          next if index.zero?

          x0, y0 = points.fetch(index - 1)
          @bitmap.line(x0, y0, x1, y1, color: COLORS.fetch((index - 1) / 12 % COLORS.length))
        end
        show_status("curve #{curve_index + 1} | Range#map + each_with_index")
      end
    end

    class PaintDemo < GraphicalDemo
      COLORS = [0xffffff, 0xff668a, 0xffd866, 0x51d6c5, 0x78dce8, 0x8f7cff, 0xc3e88d].freeze

      attr_reader :color_index

      def initialize(**options)
        super
        @color_index = 0
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT, background: 0x111827)
        build_demo_window("Ruby Paint", instructions: "Drag to paint | 1-7 colors | C clear",
                          on_key: method(:handle_key), on_pointer: method(:handle_pointer))
      end

      def clear(*)
        @bitmap.clear(0x111827)
        show_status("Canvas cleared | color #{color_index + 1}")
        true
      end

      def cycle_color(*)
        @color_index = (color_index + 1) % COLORS.length
        show_status("Color #{color_index + 1} | drag to paint")
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Paint", items: [
          GUI::MenuItem.command("Next color") { cycle_color },
          GUI::MenuItem.command("Clear", shortcut: "C") { clear }
        ]), *super]
      end

      private

      def handle_key(event)
        code = event.fetch("code", 0)
        if code.between?(49, 55)
          @color_index = code - 49
          show_status("Color #{color_index + 1} | drag to paint")
          true
        elsif [99, 67].include?(code)
          clear
        else
          false
        end
      end

      def handle_pointer(kind, x, y, _event)
        case kind
        when Input::POINTER_DOWN
          @last_point = [x, y]
          @bitmap.rect(x - 1, y - 1, 3, 3, color: COLORS.fetch(color_index))
        when Input::POINTER_MOVE
          return false unless @last_point

          @bitmap.line(*@last_point, x, y, color: COLORS.fetch(color_index))
          @bitmap.rect(x - 1, y - 1, 3, 3, color: COLORS.fetch(color_index))
          @last_point = [x, y]
        when Input::POINTER_UP
          @last_point = nil
        end
        true
      end
    end

    class LazyStarfieldDemo < GraphicalDemo
      Star = Data.define(:x, :y, :depth)

      attr_reader :stars, :frame

      def initialize(**options)
        super
        reset
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT, background: 0x02040a)
        render
        build_demo_window("Lazy Enumerator Starfield",
                          instructions: "Space pause | R reset | Enumerator.produce",
                          on_key: method(:handle_key)) { tick }
      end

      def advance(*)
        @stars = @frames.next
        @frame += 1
        render
        true
      end

      def toggle_pause(*)
        @paused = !@paused
        update_status
        true
      end

      def reset(*)
        @random = Random.new(0x53544152)
        @stars = Array.new(72) { new_star(@random.rand(0.15..1.0)) }
        @frames = Enumerator.produce(@stars) do |values|
          values.map do |star|
            depth = star.depth - 0.025
            depth <= 0.08 ? new_star(1.0) : Star.new(x: star.x, y: star.y, depth:)
          end
        end
        @frames.next
        @frame = 0
        @paused = false
        @tick_count = 0
        render if @bitmap
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Stars", items: [
          GUI::MenuItem.command("Pause / Resume", shortcut: "Space") { toggle_pause },
          GUI::MenuItem.command("Reset", shortcut: "R") { reset }
        ]), *super]
      end

      private

      def tick
        @tick_count += 1
        advance if !@paused && (@tick_count % 3).zero?
      end

      def handle_key(event)
        case event.fetch("code", 0)
        when 32 then toggle_pause
        when 114, 82 then reset
        else false
        end
      end

      def new_star(depth)
        Star.new(x: @random.rand(-0.95..0.95), y: @random.rand(-0.8..0.8), depth:)
      end

      def render
        @bitmap.clear(0x02040a)
        stars.each do |star|
          x = 80 + (star.x * 68 / star.depth).round
          y = 36 + (star.y * 32 / star.depth).round
          next unless x.between?(0, BITMAP_WIDTH - 1) && y.between?(0, BITMAP_HEIGHT - 1)

          previous_depth = [star.depth + 0.06, 1.0].min
          previous_x = 80 + (star.x * 68 / previous_depth).round
          previous_y = 36 + (star.y * 32 / previous_depth).round
          color = star.depth < 0.3 ? 0xffffff : (star.depth < 0.6 ? 0x8fcbff : 0x496785)
          @bitmap.line(previous_x, previous_y, x, y, color:)
        end
        update_status
      end

      def update_status
        show_status("Frame #{frame} | #{stars.length} immutable Data stars | #{@paused ? 'PAUSED' : 'RUNNING'}")
      end
    end

    class PalettePlasmaDemo < GraphicalDemo
      BITMAP_WIDTH = 80
      BITMAP_HEIGHT = 36
      SCALE = 4
      TABLE_SIZE = 64
      SINE = Array.new(TABLE_SIZE) do |index|
        ((Math.sin(index * Math::PI * 2.0 / TABLE_SIZE) + 1.0) * 31.5).round
      end.freeze
      PALETTES = [
        [0x13051f, 0x39245f, 0x7451b9, 0x51d6c5, 0xffd866, 0xff668a],
        [0x061826, 0x0b5269, 0x34a0a4, 0x76c893, 0xd9ed92, 0xffffff],
        [0x160b21, 0x5c1a6f, 0xa83279, 0xe95d74, 0xf6bd60, 0xf7ede2]
      ].map(&:freeze).freeze

      attr_reader :phase, :palette_index

      def initialize(**options)
        super
        @phase = 0
        @palette_index = 0
        @paused = false
        @tick_count = 0
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT)
        render
        build_demo_window("Enumerable Plasma", instructions: "Space pause | C palette | R reset",
                          scale: SCALE, on_key: method(:handle_key)) { tick }
      end

      def advance(*)
        @phase = (phase + 1) % TABLE_SIZE
        render
        true
      end

      def cycle_palette(*)
        @palette_index = (palette_index + 1) % PALETTES.length
        render
        true
      end

      def reset(*)
        @phase = 0
        render
        true
      end

      def toggle_pause(*)
        @paused = !@paused
        update_status
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Plasma", items: [
          GUI::MenuItem.command("Pause / Resume", shortcut: "Space") { toggle_pause },
          GUI::MenuItem.command("Cycle palette", shortcut: "C") { cycle_palette },
          GUI::MenuItem.command("Reset", shortcut: "R") { reset }
        ]), *super]
      end

      private

      def handle_key(event)
        case event.fetch("code", 0)
        when 32 then toggle_pause
        when 99, 67 then cycle_palette
        when 114, 82 then reset
        else false
        end
      end

      def tick
        @tick_count += 1
        advance if !@paused && (@tick_count % 3).zero?
      end

      def render
        palette = PALETTES.fetch(palette_index)
        BITMAP_HEIGHT.times do |y|
          BITMAP_WIDTH.times do |x|
            value = SINE.fetch((x * 2 + phase) % TABLE_SIZE) +
                    SINE.fetch((y * 3 + phase * 2) % TABLE_SIZE) +
                    SINE.fetch((x + y + phase * 3) % TABLE_SIZE)
            @bitmap.put(x, y, palette.fetch(value * palette.length / (TABLE_SIZE * 3)))
          end
        end
        update_status
      end

      def update_status
        show_status("Phase #{phase} | palette #{palette_index + 1} | #{@paused ? 'PAUSED' : 'RUNNING'}")
      end
    end

    class EventScopeDemo < GraphicalDemo
      KEY_CELLS = (97..122).each_with_index.to_h do |code, index|
        [code, [5 + (index % 13) * 11, 8 + (index / 13) * 18]]
      end.freeze
      SPECIAL_CELLS = {
        GUI::TextInput::LEFT_KEY => [52, 50], GUI::TextInput::RIGHT_KEY => [74, 50],
        GUI::TextInput::UP_KEY => [63, 41], GUI::TextInput::DOWN_KEY => [63, 59],
        32 => [12, 50], 13 => [118, 50]
      }.freeze

      attr_reader :events, :pressed, :pointer

      def initialize(**options)
        super
        @events = []
        @pressed = {}
        @pointer = [80, 36]
        @last_summary = "Press keys or move the pointer"
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT)
        render
        build_demo_window("Pattern Event Scope", instructions: @last_summary,
                          on_event: method(:handle_event), on_pointer: method(:handle_pointer))
      end

      def advance(*)
        handle_event("kind" => Input::KEY_DOWN, "code" => 114, "mods" => 0, "text" => "r")
      end

      def clear(*)
        @events.clear
        @pressed.clear
        @last_summary = "Event stream cleared"
        render
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Events", items: [
          GUI::MenuItem.command("Clear stream") { clear }
        ]), *super]
      end

      private

      def handle_event(event)
        case [event.fetch("kind", 0), event.fetch("code", 0)]
        in [Input::KEY_DOWN, code]
          pressed[code] = true
          record(:down, code, event.fetch("mods", 0))
        in [Input::KEY_UP, code]
          pressed.delete(code)
          record(:up, code, event.fetch("mods", 0))
        else
          return false
        end
        render
        true
      end

      def handle_pointer(kind, x, y, event)
        @pointer = [x, y]
        label = { Input::POINTER_DOWN => :down, Input::POINTER_MOVE => :move,
                  Input::POINTER_UP => :up }.fetch(kind, :pointer)
        @events << [label, x, y, event.fetch("button", 0)]
        @events = @events.last(24)
        @last_summary = "POINTER #{label.to_s.upcase}  x=#{x} y=#{y}  events=#{events.length}"
        render
        true
      end

      def record(kind, code, mods)
        @events << [kind, code, mods]
        @events = @events.last(24)
        label = code.between?(32, 126) ? code.chr.upcase : code
        @last_summary = "KEY #{kind.to_s.upcase}  #{label}  mods=#{mods}  events=#{events.length}"
      end

      def render
        @bitmap.clear(0x0a0f19)
        KEY_CELLS.merge(SPECIAL_CELLS).each do |code, (x, y)|
          color = pressed.key?(code) ? 0xffd866 : 0x34435e
          @bitmap.rect(x, y, code == 32 ? 34 : 9, 12, color:)
        end
        px, py = pointer
        @bitmap.line(px - 4, py, px + 4, py, color: 0xff668a)
        @bitmap.line(px, py - 4, px, py + 4, color: 0xff668a)
        show_status(@last_summary)
      end
    end

    class DataRainDemo < GraphicalDemo
      Drop = Data.define(:x, :y, :length, :speed, :color)
      Splash = Data.define(:x, :ttl)
      COLORS = [0x244f86, 0x3478c9, 0x55a8ff].freeze

      attr_reader :drops, :splashes, :frame

      def initialize(**options)
        super
        reset
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT)
        render
        build_demo_window("Immutable Data Rain", instructions: "Space pause | R reseed",
                          on_key: method(:handle_key)) { tick }
      end

      def advance(*)
        landed = []
        @drops = drops.map do |drop|
          y = drop.y + drop.speed
          if y >= BITMAP_HEIGHT - 2
            landed << drop.x
            spawn(above: true)
          else
            Drop.new(x: drop.x, y:, length: drop.length, speed: drop.speed, color: drop.color)
          end
        end
        @splashes = splashes.filter_map do |splash|
          Splash.new(x: splash.x, ttl: splash.ttl - 1) if splash.ttl > 1
        end + landed.map { |x| Splash.new(x:, ttl: 3) }
        @frame += 1
        render
        true
      end

      def reset(*)
        @random = Random.new(0x5241494e)
        @drops = Array.new(64) { spawn(above: false) }
        @splashes = []
        @frame = 0
        @paused = false
        @tick_count = 0
        render if @bitmap
        true
      end

      def toggle_pause(*)
        @paused = !@paused
        update_status
        true
      end

      private

      def spawn(above:)
        speed = @random.rand(2..6)
        Drop.new(x: @random.rand(0...BITMAP_WIDTH),
                 y: above ? -@random.rand(1..BITMAP_HEIGHT) : @random.rand(0...BITMAP_HEIGHT),
                 length: @random.rand(4..12), speed:, color: COLORS.fetch([speed - 2, 2].min))
      end

      def handle_key(event)
        case event.fetch("code", 0)
        when 32 then toggle_pause
        when 114, 82 then reset
        else false
        end
      end

      def tick
        @tick_count += 1
        advance if !@paused && (@tick_count % 2).zero?
      end

      def render
        @bitmap.clear(0x070b13)
        @bitmap.rect(0, BITMAP_HEIGHT - 2, BITMAP_WIDTH, 2, color: 0x182a3b)
        drops.each do |drop|
          top = [drop.y - drop.length, 0].max
          @bitmap.line(drop.x, top, drop.x, [drop.y, BITMAP_HEIGHT - 3].min, color: drop.color) if drop.y.positive?
        end
        splashes.each { |splash| @bitmap.line(splash.x - 2, BITMAP_HEIGHT - 4, splash.x + 2, BITMAP_HEIGHT - 4, color: 0x55a8ff) }
        update_status
      end

      def update_status
        show_status("Frame #{frame} | #{drops.length} immutable drops | #{@paused ? 'PAUSED' : 'RUNNING'}")
      end
    end

    class SpriteLayersDemo < GraphicalDemo
      Sprite = Data.define(:bitmap, :x, :y, :dx, :dy, :role)

      attr_reader :sprites, :missiles, :frame, :score

      def initialize(**options)
        super
        @ship_art = art(["001100", "011110", "111111", "011110"], 0x51d6c5)
        @enemy_art = art(["011110", "110011", "111111", "010010"], 0xff668a)
        @missile_art = art(["1", "1", "1"], 0xffd866)
        reset
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT)
        render
        build_demo_window("Data Sprite Layers", instructions: "Arrows/WASD move | Space fire | R reset",
                          on_key: method(:handle_key)) { tick }
      end

      def advance(*)
        @frame += 1
        @sprites = sprites.map do |sprite|
          next sprite if sprite.role == :ship

          x = sprite.x + sprite.dx
          dx = sprite.dx
          if x.negative? || x + sprite.bitmap.width >= BITMAP_WIDTH
            dx = -dx
            x = sprite.x + dx
          end
          Sprite.new(bitmap: sprite.bitmap, x:, y: sprite.y + sprite.dy,
                     dx:, dy: sprite.dy, role: sprite.role)
        end
        @missiles = missiles.filter_map do |missile|
          y = missile.y - 3
          Sprite.new(bitmap: missile.bitmap, x: missile.x, y:, dx: 0, dy: -3,
                     role: :missile) if y + missile.bitmap.height >= 0
        end
        collide
        render
        true
      end

      def reset(*)
        @sprites = [Sprite.new(bitmap: @ship_art, x: 77, y: 62, dx: 0, dy: 0, role: :ship)] +
                   5.times.map do |index|
                     Sprite.new(bitmap: @enemy_art, x: 12 + index * 29, y: 8 + index % 2 * 10,
                                dx: index.even? ? 1 : -1, dy: 0, role: :enemy)
                   end
        @missiles = []
        @score = 0
        @frame = 0
        @tick_count = 0
        render if @bitmap
        true
      end

      def fire(*)
        ship = sprites.find { |sprite| sprite.role == :ship }
        missiles << Sprite.new(bitmap: @missile_art, x: ship.x + 3, y: ship.y - 4,
                               dx: 0, dy: -3, role: :missile)
        render
        true
      end

      private

      def art(rows, color)
        bitmap = Media::Bitmap.new(rows.map(&:length).max, rows.length)
        rows.each_with_index do |row, y|
          row.each_char.with_index { |pixel, x| bitmap.put(x, y, color) if pixel == "1" }
        end
        bitmap
      end

      def handle_key(event)
        code = event.fetch("code", 0)
        direction = {
          97 => [-3, 0], 100 => [3, 0], 119 => [0, -3], 115 => [0, 3],
          GUI::TextInput::LEFT_KEY => [-3, 0], GUI::TextInput::RIGHT_KEY => [3, 0],
          GUI::TextInput::UP_KEY => [0, -3], GUI::TextInput::DOWN_KEY => [0, 3]
        }[code]
        return fire if code == 32
        return reset if [114, 82].include?(code)
        return false unless direction

        @sprites = sprites.map do |sprite|
          next sprite unless sprite.role == :ship

          Sprite.new(bitmap: sprite.bitmap,
                     x: [[sprite.x + direction[0], 0].max, BITMAP_WIDTH - sprite.bitmap.width].min,
                     y: [[sprite.y + direction[1], 25].max, BITMAP_HEIGHT - sprite.bitmap.height].min,
                     dx: 0, dy: 0, role: :ship)
        end
        render
        true
      end

      def tick
        @tick_count += 1
        advance if (@tick_count % 3).zero?
      end

      def collide
        hit_enemies = []
        missiles.each do |missile|
          enemy = sprites.find do |sprite|
            sprite.role == :enemy && missile.x.between?(sprite.x, sprite.x + sprite.bitmap.width - 1) &&
              missile.y.between?(sprite.y, sprite.y + sprite.bitmap.height - 1)
          end
          hit_enemies << enemy if enemy
        end
        return if hit_enemies.empty?

        @sprites = sprites.reject { |sprite| hit_enemies.include?(sprite) }
        @missiles = missiles.reject do |missile|
          hit_enemies.any? { |enemy| missile.x.between?(enemy.x, enemy.x + enemy.bitmap.width - 1) &&
            missile.y.between?(enemy.y, enemy.y + enemy.bitmap.height - 1) }
        end
        @score += hit_enemies.uniq.length * 100
      end

      def render
        @bitmap.clear(0x030817)
        36.times { |index| @bitmap.put((index * 47 + frame) % BITMAP_WIDTH, 4 + index * 19 % 56, 0x304968) }
        sprites.each { |sprite| @bitmap.blit(sprite.bitmap, sprite.x, sprite.y, key: 0) }
        missiles.each { |sprite| @bitmap.blit(sprite.bitmap, sprite.x, sprite.y, key: 0) }
        show_status("Frame #{frame} | #{sprites.length} immutable sprites | Score #{score}")
      end
    end

    class ToneLabDemo < GraphicalDemo
      NOTES = [220, 262, 330, 392, 440, 523, 659, 784].freeze
      WAVEFORMS = %i[sine square triangle].freeze

      attr_reader :note_index, :waveform_index, :plays, :last_queued

      def initialize(**options)
        super
        @note_index = 4
        @waveform_index = 0
        @chord = false
        @plays = 0
        @last_queued = 0
      end

      def build_window
        @bitmap ||= Media::Bitmap.new(BITMAP_WIDTH, BITMAP_HEIGHT)
        render
        build_demo_window("Ruby Tone Lab", instructions: "Up/Down pitch | W wave | C chord | Space play",
                          on_key: method(:handle_key))
      end

      def frequency = NOTES.fetch(note_index)
      def waveform = WAVEFORMS.fetch(waveform_index)

      def change_note(delta)
        @note_index = [[note_index + Integer(delta), 0].max, NOTES.length - 1].min
        render
        true
      end

      def cycle_waveform(*)
        @waveform_index = (waveform_index + 1) % WAVEFORMS.length
        render
        true
      end

      def toggle_chord(*)
        @chord = !@chord
        render
        true
      end

      def play(*)
        client = @compositor&.file_transfer&.client
        output = @compositor&.audio_output
        unless output || client&.features&.include?("audio.pcm")
          show_status("Audio bridge unavailable | #{frequency} Hz #{waveform}")
          return false
        end

        owned_output = !output
        output ||= Sound::BridgeOutput.new(client)
        voice = Sound::Waveform.public_send(waveform, frequency, duration_ms: 180, amplitude: 0.18)
        if @chord
          harmony = Sound::Waveform.public_send(waveform, frequency * 1.5,
                                                duration_ms: 180, amplitude: 0.12)
          voice = Sound::Mixer.new.mix(voice, harmony)
        end
        output.play(voice)
        @last_queued = output.queued_bytes
        @plays += 1
        output.close if owned_output
        render
        true
      ensure
        output&.close if owned_output
      end
      alias advance play

      private

      def handle_key(event)
        case event.fetch("code", 0)
        when GUI::TextInput::UP_KEY then change_note(1)
        when GUI::TextInput::DOWN_KEY then change_note(-1)
        when 119, 87 then cycle_waveform
        when 99, 67 then toggle_chord
        when 32 then play
        else false
        end
      end

      def render
        @bitmap.clear(0x080b14)
        preview = Sound::Waveform.public_send(waveform, frequency, duration_ms: 20,
                                             amplitude: 0.8, rate: 8_000)
        samples = preview.samples
        BITMAP_WIDTH.times do |x|
          sample = samples.fetch(x * samples.length / BITMAP_WIDTH)
          y = 36 - (sample * 28 / 32_767)
          @bitmap.line(x - 1, @last_y || y, x, y, color: 0x51d6c5) if x.positive?
          @last_y = y
        end
        mode = @chord ? "chord" : "single"
        show_status("#{frequency} Hz | #{waveform} | #{mode} | played #{plays}")
      ensure
        @last_y = nil
      end
    end
  end
end
