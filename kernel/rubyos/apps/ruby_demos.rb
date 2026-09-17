# frozen_string_literal: true

module RubyOS
  module Apps
    # The launcher is the public catalog rather than a hard-coded second dock.
    # Registry metadata drives it, so live applications and future demos share
    # the same launch path as built-ins.
    class Launcher < Application
      def initialize(registry:, **options)
        super(**options)
        @registry = registry
      end

      def build_window
        window_x, window_y = spacious_desktop? ? [116, 44] : [74, 34]
        window_width, window_height = spacious_desktop? ? [408, 300] : [360, 210]
        content_width = window_width - 36
        list_height = window_height - 110
        window = GUI::Window.new("RubyOS Applications", x: window_x, y: window_y,
                                 width: window_width, height: window_height,
                                 background: 0x151c29)
        window.add(GUI::Label.new("APPS, DEMOS & GAMES", x: 8, y: 4,
                                  width: 260, color: 0x8f7cff))
        items = @registry.entries.reject { |entry| entry.application.equal?(self) }.map do |entry|
          { label: "#{entry.category.to_s.upcase.ljust(4)}  #{entry.name}",
            kind: :file, entry: }
        end
        list = window.add(GUI::ListView.new(items:, x: 8, y: 30,
                                            width: content_width, height: list_height,
                                            background: 0x1d2535,
                                            on_activate: method(:launch_entry)),
                          anchors: [:left, :right, :top, :bottom],
                          minimum_width: 80, minimum_height: 30)
        @status = window.add(GUI::Label.new("#{items.length} entries | arrows + Enter", x: 8,
                                            y: 40 + list_height,
                                            width: content_width, color: 0xa8d8ff),
                              anchors: [:left, :right, :bottom], minimum_width: 80)
        window.focus_child(list)
        window
      end

      def launch_entry(item)
        entry = item.fetch(:entry)
        @status.text = entry.description
        @status.invalidate
        entry.application.launch(@compositor)
      end
    end

    # A visual tour of chained Enumerable transformations. The data and
    # operations are ordinary Ruby objects; the GUI only presents each stage.
    class EnumerableLab < Application
      PIPELINES = [
        ["select(&:odd?)", (1..10).to_a, ->(values) { values.select(&:odd?) }],
        ["map { _1 ** 2 }", [1, 3, 5, 7, 9], ->(values) { values.map { |value| value**2 } }],
        ["each_slice(2).map(&:sum)", [1, 9, 25, 49, 81],
         ->(values) { values.each_slice(2).map(&:sum) }],
        ["reduce(:+)", [10, 74, 81], ->(values) { values.reduce(:+) }]
      ].each(&:freeze).freeze

      def initialize(**options)
        super
        @step = 0
      end

      def build_window
        window_x, window_y = spacious_desktop? ? [88, 54] : [50, 34]
        window_width, window_height = spacious_desktop? ? [452, 250] : [380, 210]
        content_width = window_width - 36
        @window = GUI::Window.new("Enumerable Pipeline", x: window_x, y: window_y,
                                  width: window_width, height: window_height,
                                  background: 0x171522)
        @window.add(GUI::Label.new("RUBY PIPELINE", x: 8, y: 4, width: 160,
                                   color: 0x8f7cff))
        @operation = @window.add(GUI::Label.new("", x: 8, y: 34, width: content_width,
                                                 color: 0xffd866),
                                  anchors: [:left, :right, :top], minimum_width: 80)
        @input = @window.add(GUI::Label.new("", x: 8, y: 64, width: content_width,
                                             height: 38, wrap: true, color: 0xa8d8ff),
                              anchors: [:left, :right, :top], minimum_width: 80)
        @result = @window.add(GUI::Label.new("", x: 8, y: 106, width: content_width,
                                              height: 38, wrap: true, color: 0xc3e88d),
                               anchors: [:left, :right, :top], minimum_width: 80)
        @window.add(GUI::Button.new("Next stage", x: 8, y: window_height - 72,
                                    width: 112, height: 26,
                                    action: method(:advance)), anchors: [:left, :bottom])
        render_step
        @window
      end

      def advance(*)
        @step = (@step + 1) % PIPELINES.length
        render_step
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Pipeline", items: [
          GUI::MenuItem.command("Next stage") { advance }
        ]), *super]
      end

      private

      def render_step
        name, input, operation = PIPELINES.fetch(@step)
        @operation.text = "#{@step + 1}. #{name}"
        @input.text = "input   #{input.inspect}"
        @result.text = "result  #{operation.call(input).inspect}"
        @window.invalidate
        true
      end
    end

    class FiberLab < Application
      def build_window
        window_x, window_y = spacious_desktop? ? [106, 62] : [50, 34]
        window_width, window_height = spacious_desktop? ? [420, 228] : [380, 210]
        content_width = window_width - 36
        @window = GUI::Window.new("Fiber Choreography", x: window_x, y: window_y,
                                  width: window_width, height: window_height,
                                  background: 0x131824)
        @window.add(GUI::Label.new("COOPERATIVE EXECUTION", x: 8, y: 4,
                                   width: 220, color: 0x8f7cff))
        @trace = @window.add(GUI::Label.new("", x: 8, y: 38, width: content_width,
                                             height: 70, wrap: true, color: 0x78dce8),
                              anchors: [:left, :right, :top], minimum_width: 80)
        @state = @window.add(GUI::Label.new("", x: 8, y: 116, width: content_width,
                                             color: 0xc3e88d),
                              anchors: [:left, :right, :top], minimum_width: 80)
        @window.add(GUI::Button.new("Resume", x: 8, y: window_height - 72,
                                    width: 88, height: 26,
                                    action: method(:resume)), anchors: [:left, :bottom])
        reset
        @window
      end

      def resume(*)
        reset unless @fiber.alive?
        value = @fiber.resume
        @events << value if value
        @trace.text = @events.join("  ->  ")
        @state.text = @fiber.alive? ? "Fiber suspended at yield" : "Fiber complete; Resume restarts"
        @window.invalidate
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Fiber", items: [
          GUI::MenuItem.command("Resume") { resume }
        ]), *super]
      end

      private

      def reset
        @events = []
        @fiber = Fiber.new do
          Fiber.yield("connect")
          Fiber.yield("read")
          Fiber.yield("render")
          "done"
        end
        @trace.text = "Click Resume to cross each Fiber.yield" if @trace
        @state.text = "Fiber created" if @state
      end
    end

    class PatternLab < Application
      EVENTS = [
        { kind: :key, code: 114, text: "r" },
        { kind: :pointer, at: [120, 80], button: 1 },
        { kind: :device, payload: { name: "virtio-net", bound: true } }
      ].each(&:freeze).freeze

      def initialize(**options)
        super
        @index = 0
      end

      def build_window
        window_x, window_y = spacious_desktop? ? [126, 72] : [50, 34]
        window_width, window_height = spacious_desktop? ? [398, 216] : [380, 210]
        content_width = window_width - 36
        @window = GUI::Window.new("Pattern Matching", x: window_x, y: window_y,
                                  width: window_width, height: window_height,
                                  background: 0x181425)
        @window.add(GUI::Label.new("CASE / IN", x: 8, y: 4, width: 120,
                                   color: 0x8f7cff))
        @event = @window.add(GUI::Label.new("", x: 8, y: 36, width: content_width,
                                             height: 42, wrap: true, color: 0xffd866),
                              anchors: [:left, :right, :top], minimum_width: 80)
        @match = @window.add(GUI::Label.new("", x: 8, y: 88, width: content_width,
                                             height: 42, wrap: true, color: 0xc3e88d),
                              anchors: [:left, :right, :top], minimum_width: 80)
        @window.add(GUI::Button.new("Next value", x: 8, y: window_height - 68,
                                    width: 104, height: 26,
                                    action: method(:advance)), anchors: [:left, :bottom])
        render_match
        @window
      end

      def advance(*)
        @index = (@index + 1) % EVENTS.length
        render_match
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Pattern", items: [
          GUI::MenuItem.command("Next value") { advance }
        ]), *super]
      end

      private

      def render_match
        value = EVENTS.fetch(@index)
        result = case value
                 in kind: :key, text:
                   "keyboard text => #{text.inspect}"
                 in kind: :pointer, at: [x, y], button:
                   "button #{button} at #{x},#{y}"
                 in kind: :device, payload: { name:, bound: true }
                   "bound device => #{name}"
                 else
                   "no match"
                 end
        @event.text = value.inspect
        @match.text = result
        @window.invalidate
        true
      end
    end
  end
end
