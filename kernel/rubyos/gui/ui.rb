# frozen_string_literal: true

module RubyOS
  module GUI
    class Element
      attr_accessor :parent, :visible, :enabled, :focused

      def initialize(visible: true, enabled: true)
        @visible = visible
        @enabled = enabled
        @focused = false
      end

      def invalidate
        node = self
        node = node.parent until node.nil? || node.respond_to?(:dirty=)
        node.dirty = true if node
      end

      def focusable? = false
    end

    class View < Element
      attr_accessor :x, :y, :width, :height, :background

      def initialize(x: 0, y: 0, width: 0, height: 0, background: nil, **)
        super(**)
        @x, @y, @width, @height = x, y, width, height
        @background = background
      end

      def contains?(point_x, point_y)
        x <= point_x && point_x < x + width && y <= point_y && point_y < y + height
      end

      def draw(surface)
        surface.fill_rect(x, y, width, height, background) if visible && background
      end

      def handle(_event)
        false
      end
    end

    class Container < View
      attr_reader :children

      def initialize(**)
        super
        @children = []
      end

      def add(child)
        child.parent = self
        children << child
        invalidate
        child
      end

      def draw(surface)
        super
        children.each { |child| child.draw(surface) if child.visible }
      end
    end

    class Label < View
      CHARACTER_WIDTH = 8
      LINE_HEIGHT = 20

      attr_accessor :text, :color

      def initialize(text, color: 0xffffff, wrap: false, **)
        super(**)
        @text, @color = text, color
        @wrap = wrap
      end

      def draw(surface)
        super
        return unless visible

        display_lines.each_with_index do |line, index|
          surface.draw_text(x, y + index * LINE_HEIGHT, line, color:)
        end
      end

      private

      def display_lines
        available_width = width.positive? ? width : [parent&.width.to_i - x - 20, CHARACTER_WIDTH].max
        columns = [available_width / CHARACTER_WIDTH, 1].max
        rows = height.positive? ? [height / LINE_HEIGHT, 1].max : 1
        source = String(text).split("\n", -1)
        lines = if @wrap
                  source.flat_map { |line| line.empty? ? [""] : line.each_char.each_slice(columns).map(&:join) }
                else
                  source.map { |line| ellipsize(line, columns) }
                end
        lines.first(rows)
      end

      def ellipsize(line, columns)
        characters = line.each_char.to_a
        return line if characters.length <= columns
        return characters.first(columns).join if columns < 4

        characters.first(columns - 3).join + "..."
      end
    end

    class Button < Label
      def initialize(text, action: nil, **)
        super(text, **)
        @action = action
      end

      def handle(event)
        keyboard_click = event.respond_to?(:fetch) && event.fetch("kind", 0) == 1 &&
                         [13, 32].include?(event.fetch("code", 0))
        return false unless event == :click || (focused && keyboard_click)

        @action&.call(self)
        invalidate
        true
      end


      def draw(surface)
        surface.fill_rect(x, y, width, height, focused ? 0x7048a8 : (background || 0x49325f))
        surface.fill_rect(x, y + height - 2, width, 2, focused ? 0xb792ff : 0x32243f)
        surface.draw_text(x + 7, y + [(height - 12) / 2, 2].max, text,
                          color: focused ? 0xffffff : color)
      end

      def focusable? = true
    end

    class TextInput < View
      LEFT_KEY = 1_073_741_904
      RIGHT_KEY = 1_073_741_903
      HOME_KEY = 1_073_741_898
      END_KEY = 1_073_741_897

      attr_reader :text, :cursor

      def initialize(text: "", color: 0xffffff, multiline: false,
                     on_change: nil, on_submit: nil, **options)
        super(**options)
        @text = String(text).dup
        @cursor = @text.each_char.count
        @color = color
        @multiline = multiline
        @on_change = on_change
        @on_submit = on_submit
      end

      def draw(surface)
        super
        lines = visible_lines
        lines.each_with_index { |line, index| surface.draw_text(x + 4, y + 4 + index * 20, line, color: @color) }
        if focused
          cursor_column = @multiline ? lines.last.to_s.each_char.count : visible_cursor_column
          surface.draw_text(x + 4 + cursor_column * 8,
                            y + 4 + (lines.length - 1) * 20, "_", color: 0xffd866)
        end
      end

      def handle(event)
        return false unless event.respond_to?(:fetch)
        return false unless event.fetch("kind", 0) == 1
        code = event.fetch("code", 0)
        typed = event.fetch("text", "")
        if code == 8
          characters = text.each_char.to_a
          if cursor.positive?
            characters.delete_at(cursor - 1)
            @cursor -= 1
            replace(characters.join)
          end
        elsif code == 127
          characters = text.each_char.to_a
          characters.delete_at(cursor) if cursor < characters.length
          replace(characters.join)
        elsif code == LEFT_KEY
          @cursor = [cursor - 1, 0].max
        elsif code == RIGHT_KEY
          @cursor = [cursor + 1, text.each_char.count].min
        elsif code == HOME_KEY
          @cursor = 0
        elsif code == END_KEY
          @cursor = text.each_char.count
        elsif code == 13
          @multiline ? insert("\n") : @on_submit&.call(text)
        elsif !typed.empty?
          insert(typed)
        else
          return false
        end
        invalidate
        true
      end

      def replace(value)
        @text = String(value)
        @cursor = [cursor, @text.each_char.count].min
        @on_change&.call(@text)
        self
      end

      def focusable? = true

      private

      def columns = [[(width - 8) / 8, 1].max, 1].max

      def visible_lines
        lines = text.split("\n", -1).last([height / 20, 1].max)
        return lines if @multiline

        characters = lines.last.to_s.each_char.to_a
        start = [[cursor - columns + 1, 0].max, [characters.length - columns, 0].max].min
        [characters.slice(start, columns).to_a.join]
      end

      def visible_cursor_column
        start = [cursor - columns + 1, 0].max
        cursor - start
      end

      def insert(value)
        characters = text.each_char.to_a
        inserted = String(value).each_char.to_a
        characters.insert(cursor, *inserted)
        @cursor += inserted.length
        replace(characters.join)
      end
    end


    class ListView < View
      ROW_HEIGHT = 26
      UP_KEYS = [1_073_741_906].freeze
      DOWN_KEYS = [1_073_741_905].freeze

      attr_reader :items, :selected_index

      def initialize(items: [], on_activate: nil, on_cancel: nil, **options)
        super(**options)
        @items = items
        @selected_index = items.empty? ? nil : 0
        @on_activate = on_activate
        @on_cancel = on_cancel
        @scroll_offset = 0
      end

      def replace(items)
        @items = Array(items)
        @selected_index = items.empty? ? nil : [[selected_index || 0, items.length - 1].min, 0].max
        keep_selected_visible
        invalidate
        self
      end

      def selected_item
        selected_index && items[selected_index]
      end

      def draw(surface)
        super
        visible_rows.times do |row|
          index = @scroll_offset + row
          item = items[index]
          break unless item

          row_y = y + row * ROW_HEIGHT
          if index == selected_index
            surface.fill_rect(x, row_y, width, ROW_HEIGHT - 2, focused ? 0x553184 : 0x3b3150)
          end
          icon = item.fetch(:kind, :file) == :directory ? ">" : "-"
          color = item.fetch(:kind, :file) == :directory ? 0xb9dcff : 0xe8dff5
          label = "#{icon}  #{item.fetch(:label)}"
          max = [(width - 16) / 8, 1].max
          label = label.each_char.first(max - 3).join + "..." if label.each_char.count > max
          surface.draw_text(x + 8, row_y + 7, label, color:)
        end
      end

      def handle(event)
        return false unless focused && event.respond_to?(:fetch)
        return false unless event.fetch("kind", 0) == 1

        code = event.fetch("code", 0)
        if UP_KEYS.include?(code)
          move(-1)
        elsif DOWN_KEYS.include?(code)
          move(1)
        elsif code == 13
          activate
        elsif code == 8 || code == 27
          @on_cancel&.call
          invalidate
          true
        else
          false
        end
      end

      def handle_pointer(local_x, local_y, _event)
        return false unless contains?(local_x, local_y)

        index = @scroll_offset + (local_y - y) / ROW_HEIGHT
        return false unless items[index]

        @selected_index = index
        activate
      end

      def focusable? = true

      private

      def visible_rows = [height / ROW_HEIGHT, 1].max

      def move(delta)
        return false if items.empty?

        @selected_index = [[(selected_index || 0) + delta, 0].max, items.length - 1].min
        keep_selected_visible
        invalidate
        true
      end

      def keep_selected_visible
        return unless selected_index
        @scroll_offset = selected_index if selected_index < @scroll_offset
        @scroll_offset = selected_index - visible_rows + 1 if selected_index >= @scroll_offset + visible_rows
        @scroll_offset = [@scroll_offset, 0].max
      end

      def activate
        item = selected_item
        return false unless item

        @on_activate&.call(item)
        invalidate
        true
      end
    end


    class Meter < View
      attr_accessor :value, :maximum, :label, :color

      def initialize(value:, maximum:, label: "", color: 0x78dce8, **options)
        super(**options)
        @value, @maximum, @label, @color = value, maximum, label, color
      end

      def draw(surface)
        surface.fill_rect(x, y, width, height, background || 0x292235)
        ratio = maximum.to_f.zero? ? 0.0 : [[value.to_f / maximum, 0.0].max, 1.0].min
        surface.fill_rect(x, y, (width * ratio).to_i, height, color)
        surface.draw_text(x + 6, y + 4, label, color: 0xffffff)
      end
    end
  end
end
