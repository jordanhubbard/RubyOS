# frozen_string_literal: true

module RubyOS
  module Apps
    class DemoCanvas < GUI::View
      attr_reader :bitmap, :scale

      def initialize(bitmap:, scale: 1, on_key: nil, on_pointer: nil, **options)
        @bitmap = bitmap
        @scale = Integer(scale)
        raise ArgumentError, "canvas scale must be positive" unless @scale.positive?

        @on_key = on_key
        @on_pointer = on_pointer
        @pointer_captured = false
        super(width: bitmap.width * @scale, height: bitmap.height * @scale, **options)
      end

      def draw(surface)
        super
        surface.draw_bitmap(x, y, bitmap, scale:)
      end

      def handle(event)
        return false unless focused && event.fetch("kind", 0) == Input::KEY_DOWN && @on_key

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
                            on_key: nil, on_pointer: nil, &tick)
        window_x, window_y = spacious_desktop? ? [148, 72] : [66, 30]
        @window = GUI::Window.new(title, x: window_x, y: window_y,
                                  width: 344, height: 222, resizable: false,
                                  background: 0x111827)
        @canvas = @window.add(DemoCanvas.new(
          bitmap: @bitmap, scale:, x: 0, y: 0,
          on_key:, on_pointer:
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
  end
end
