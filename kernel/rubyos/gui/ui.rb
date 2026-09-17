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
      def pointer_capture? = false
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

    class Clipboard
      def self.default = (@default ||= new)

      def initialize
        @text = +""
      end

      def read = @text.dup

      def write(value)
        @text = String(value).dup
        self
      end

      def clear
        @text.clear
        self
      end

      def empty? = @text.empty?
    end

    class TextView < View
      UP_KEY = 1_073_741_906
      DOWN_KEY = 1_073_741_905
      HOME_KEY = 1_073_741_898
      END_KEY = 1_073_741_897
      PAGE_UP_KEY = 1_073_741_899
      PAGE_DOWN_KEY = 1_073_741_900

      attr_reader :text, :scroll_line, :clipboard
      attr_accessor :color

      def initialize(text: "", color: 0xffffff, wrap: false,
                     clipboard: Clipboard.default, **options)
        super(**options)
        @text = String(text).dup
        @color = Integer(color)
        @wrap = !!wrap
        @clipboard = clipboard
        @scroll_line = 0
      end

      def replace(value, scroll: nil)
        @text = String(value).dup
        clamp_scroll
        scroll_to(0) if scroll == :start
        scroll_to_end if scroll == :end
        invalidate
        self
      end

      def append(value)
        following = at_end?
        @text << String(value)
        clamp_scroll
        scroll_to_end if following
        invalidate
        self
      end

      def scroll_to_end
        @scroll_line = maximum_scroll
        invalidate
        self
      end

      def scroll_to_start
        scroll_to(0)
        self
      end

      def at_end? = scroll_line >= maximum_scroll

      def draw(surface)
        super
        lines = display_lines
        lines.slice(scroll_line, row_count).to_a.each_with_index do |line, row|
          surface.draw_text(x + 5, y + 4 + row * Label::LINE_HEIGHT, line, color:)
        end
        surface.draw_text(x + width - 13, y + 4, "^", color: 0x8f7cff) if scroll_line.positive?
        if scroll_line < maximum_scroll
          surface.draw_text(x + width - 13, y + height - 16, "v", color: 0x8f7cff)
        end
      end

      def handle(event)
        return false unless focused && event.respond_to?(:fetch)

        kind = event.fetch("kind", 0)
        if kind == Input::POINTER_WHEEL
          delta = event.fetch("dy", 0)
          delta = event.fetch("dx", 0) if delta.zero?
          return scroll(delta.positive? ? -3 : 3)
        end
        return false unless kind == Input::KEY_DOWN

        case event.fetch("code", 0)
        when UP_KEY then scroll(-1)
        when DOWN_KEY then scroll(1)
        when PAGE_UP_KEY then scroll(-row_count)
        when PAGE_DOWN_KEY then scroll(row_count)
        when HOME_KEY then scroll_to(0)
        when END_KEY then scroll_to(maximum_scroll)
        else false
        end
      end

      def context_menu_items
        [MenuItem.command("Copy all", enabled: !text.empty?) { clipboard.write(text) },
         MenuItem.command("Scroll to end", enabled: !at_end?) { scroll_to_end }]
      end

      def focusable? = true

      private

      def columns = [[(width - 18) / Label::CHARACTER_WIDTH, 1].max, 240].min
      def row_count = [[(height - 8) / Label::LINE_HEIGHT, 1].max, 200].min

      def display_lines
        source = text.split("\n", -1)
        return source unless @wrap

        source.flat_map do |line|
          line.empty? ? [""] : line.each_char.each_slice(columns).map(&:join)
        end
      end

      def maximum_scroll = [display_lines.length - row_count, 0].max

      def clamp_scroll
        @scroll_line = [[scroll_line, 0].max, maximum_scroll].min
      end

      def scroll(delta)
        scroll_to(scroll_line + Integer(delta))
      end

      def scroll_to(value)
        previous = scroll_line
        @scroll_line = [[Integer(value), 0].max, maximum_scroll].min
        invalidate if previous != scroll_line
        previous != scroll_line
      end
    end

    class TextInput < View
      LEFT_KEY = 1_073_741_904
      RIGHT_KEY = 1_073_741_903
      UP_KEY = 1_073_741_906
      DOWN_KEY = 1_073_741_905
      HOME_KEY = 1_073_741_898
      END_KEY = 1_073_741_897
      PAGE_UP_KEY = 1_073_741_899
      PAGE_DOWN_KEY = 1_073_741_900

      attr_reader :text, :cursor, :scroll_line, :scroll_column, :clipboard

      def initialize(text: "", color: 0xffffff, multiline: false,
                     on_change: nil, on_submit: nil, on_history: nil,
                     clipboard: Clipboard.default, **options)
        super(**options)
        @text = String(text).dup
        @cursor = @text.each_char.count
        @color = color
        @multiline = multiline
        @on_change = on_change
        @on_submit = on_submit
        @on_history = on_history
        @clipboard = clipboard
        @selection_anchor = nil
        @pointer_selecting = false
        @scroll_line = 0
        @scroll_column = 0
        ensure_cursor_visible
      end

      def draw(surface)
        super
        lines = visible_lines
        draw_selection(surface)
        lines.each_with_index { |line, index| surface.draw_text(x + 4, y + 4 + index * 20, line, color: @color) }
        if focused
          line, column = cursor_position
          row = @multiline ? line - scroll_line : 0
          if row.between?(0, row_count - 1)
            surface.draw_text(x + 4 + (column - scroll_column) * 8,
                              y + 4 + row * 20, "_", color: 0xffd866)
          end
        end
      end

      def handle(event)
        return false unless event.respond_to?(:fetch)
        if event.fetch("kind", 0) == Input::POINTER_WHEEL && @multiline
          delta = event.fetch("dy", 0)
          delta = event.fetch("dx", 0) if delta.zero?
          return scroll(delta.positive? ? -3 : 3)
        end
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN
        code = event.fetch("code", 0)
        mods = event.fetch("mods", 0)
        typed = event.fetch("text", "")
        if (mods & Input::MOD_CTRL) != 0
          return handle_clipboard_key(code)
        end
        extend_selection = (mods & Input::MOD_SHIFT) != 0
        if code == 8
          delete_backward
        elsif code == 127
          delete_forward
        elsif code == LEFT_KEY
          move_cursor(cursor - 1, extend: extend_selection)
        elsif code == RIGHT_KEY
          move_cursor(cursor + 1, extend: extend_selection)
        elsif @multiline && code == UP_KEY
          move_cursor(vertical_target(-1), extend: extend_selection)
        elsif @multiline && code == DOWN_KEY
          move_cursor(vertical_target(1), extend: extend_selection)
        elsif !@multiline && @on_history && [UP_KEY, DOWN_KEY].include?(code)
          replacement = @on_history.call(code == UP_KEY ? -1 : 1)
          if replacement
            replace(replacement, notify: false)
            move_cursor(text.each_char.count)
          end
        elsif @multiline && code == PAGE_UP_KEY
          move_cursor(vertical_target(-row_count), extend: extend_selection)
        elsif @multiline && code == PAGE_DOWN_KEY
          move_cursor(vertical_target(row_count), extend: extend_selection)
        elsif code == HOME_KEY
          target = @multiline ? line_start(cursor_position.first) : 0
          move_cursor(target, extend: extend_selection)
        elsif code == END_KEY
          target = @multiline ? line_end(cursor_position.first) : text.each_char.count
          move_cursor(target, extend: extend_selection)
        elsif code == 13
          @multiline ? insert("\n") : @on_submit&.call(text)
        elsif !typed.empty?
          insert(typed)
        else
          return false
        end
        ensure_cursor_visible
        invalidate
        true
      end

      def selection_range
        return nil unless @selection_anchor && @selection_anchor != cursor

        [@selection_anchor, cursor].minmax
      end

      def selected_text
        range = selection_range
        range ? text.each_char.to_a.slice(range.first...range.last).join : ""
      end

      def select_all
        @selection_anchor = 0
        @cursor = text.each_char.count
        ensure_cursor_visible
        invalidate
        self
      end

      def copy
        clipboard.write(selected_text) if selection_range
        self
      end

      def cut
        copy
        delete_selection
        self
      end

      def paste
        insert(clipboard.read)
        self
      end

      def handle_pointer(local_x, local_y, event)
        kind = event.fetch("kind", Input::POINTER_DOWN)
        return false if kind == Input::POINTER_DOWN && !contains?(local_x, local_y)
        return false if kind != Input::POINTER_DOWN && !pointer_capture?

        position = cursor_at(local_x, local_y)
        if kind == Input::POINTER_DOWN
          @cursor = position
          @selection_anchor = position
          @pointer_selecting = true
        elsif kind == Input::POINTER_MOVE
          @cursor = position
        elsif kind == Input::POINTER_UP
          @cursor = position
          @pointer_selecting = false
          @selection_anchor = nil if @selection_anchor == cursor
        end
        ensure_cursor_visible
        invalidate
        true
      end

      def replace(value, notify: true)
        @text = String(value)
        @cursor = [cursor, @text.each_char.count].min
        @selection_anchor = nil
        ensure_cursor_visible
        @on_change&.call(@text) if notify
        self
      end

      def move_cursor(position, extend: false)
        previous = cursor
        @selection_anchor = extend ? (@selection_anchor || previous) : nil
        @cursor = [[Integer(position), 0].max, text.each_char.count].min
        ensure_cursor_visible
        invalidate
        self
      end

      def context_menu_items
        has_selection = !selection_range.nil?
        [
          MenuItem.command("Cut", shortcut: "Ctrl+X", enabled: has_selection) { cut },
          MenuItem.command("Copy", shortcut: "Ctrl+C", enabled: has_selection) { copy },
          MenuItem.command("Paste", shortcut: "Ctrl+V", enabled: !clipboard.empty?) { paste },
          MenuItem.separator,
          MenuItem.command("Select All", shortcut: "Ctrl+A", enabled: !text.empty?) { select_all }
        ]
      end

      def focusable? = true
      def pointer_capture? = @pointer_selecting

      private

      def columns = [(width - 8) / 8, 1].max
      def row_count = [(height - 8) / 20, 1].max

      def logical_lines = text.split("\n", -1)

      def visible_lines
        lines = @multiline ? logical_lines.slice(scroll_line, row_count).to_a : [text]
        lines.map { |line| line.each_char.drop(scroll_column).first(columns).join }
      end

      def draw_selection(surface)
        range = selection_range
        return unless range

        visible_lines.each_index do |row|
          line = @multiline ? scroll_line + row : 0
          start_at = line_start(line)
          length = logical_lines.fetch(line).each_char.count
          from = [range.first - start_at, 0].max
          to = [range.last - start_at, length].min
          next unless to > from

          visible_from = [from - scroll_column, 0].max
          visible_to = [to - scroll_column, columns].min
          next unless visible_to > visible_from

          surface.fill_rect(x + 4 + visible_from * 8, y + 4 + row * 20,
                            (visible_to - visible_from) * 8, 16, 0x553184)
        end
      end

      def cursor_position
        prefix = text.each_char.first(cursor).join
        lines = prefix.split("\n", -1)
        [lines.length - 1, lines.last.to_s.each_char.count]
      end

      def line_start(line)
        logical_lines.first(line).sum { |value| value.each_char.count + 1 }
      end

      def line_end(line)
        line_start(line) + logical_lines.fetch(line).each_char.count
      end

      def vertical_target(delta)
        line, column = cursor_position
        target = [[line + delta, 0].max, logical_lines.length - 1].min
        line_start(target) + [column, logical_lines.fetch(target).each_char.count].min
      end

      def cursor_at(local_x, local_y)
        if @multiline
          lines = logical_lines
          row = (local_y - y - 4) / 20
          line = [[scroll_line + row, 0].max, lines.length - 1].min
          column = [[scroll_column + (local_x - x - 4) / 8, 0].max,
                    lines.fetch(line).each_char.count].min
          line_start(line) + column
        else
          [[scroll_column + (local_x - x - 4) / 8, 0].max,
           text.each_char.count].min
        end
      end

      def handle_clipboard_key(code)
        case code
        when 97, 65
          select_all
        when 99, 67
          copy
        when 120, 88
          cut
        when 118, 86
          paste
        else
          return false
        end
        invalidate
        true
      end

      def delete_backward
        return true if delete_selection
        return true unless cursor.positive?

        characters = text.each_char.to_a
        characters.delete_at(cursor - 1)
        @cursor -= 1
        replace(characters.join)
        true
      end

      def delete_forward
        return true if delete_selection
        return true unless cursor < text.each_char.count

        characters = text.each_char.to_a
        characters.delete_at(cursor)
        replace(characters.join)
        true
      end

      def delete_selection
        range = selection_range
        return false unless range

        characters = text.each_char.to_a
        characters.slice!(range.first...range.last)
        @cursor = range.first
        @selection_anchor = nil
        replace(characters.join)
        true
      end

      def ensure_cursor_visible
        line, column = cursor_position
        if @multiline
          @scroll_line = line if line < scroll_line
          @scroll_line = line - row_count + 1 if line >= scroll_line + row_count
        else
          @scroll_line = 0
        end
        @scroll_column = column if column < scroll_column
        @scroll_column = column - columns + 1 if column >= scroll_column + columns
        @scroll_line = [@scroll_line, 0].max
        @scroll_column = [@scroll_column, 0].max
      end

      def scroll(delta)
        maximum = [logical_lines.length - row_count, 0].max
        previous = scroll_line
        @scroll_line = [[scroll_line + delta, 0].max, maximum].min
        invalidate if previous != scroll_line
        previous != scroll_line
      end

      def insert(value)
        characters = text.each_char.to_a
        if (range = selection_range)
          characters.slice!(range.first...range.last)
          @cursor = range.first
        end
        inserted = String(value).each_char.to_a
        characters.insert(cursor, *inserted)
        @cursor += inserted.length
        @selection_anchor = nil
        replace(characters.join)
      end
    end


    class ListView < View
      ROW_HEIGHT = 26
      UP_KEYS = [1_073_741_906].freeze
      DOWN_KEYS = [1_073_741_905].freeze

      attr_reader :items, :selected_index, :scroll_offset

      def initialize(items: [], on_activate: nil, on_back: nil, on_cancel: nil, **options)
        super(**options)
        @items = items
        @selected_index = items.empty? ? nil : 0
        @on_activate = on_activate
        @on_back = on_back
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

      def item_at(point_x, point_y)
        return nil unless contains?(point_x, point_y)

        items[scroll_offset + (point_y - y) / ROW_HEIGHT]
      end

      def draw(surface)
        super
        visible_rows.times do |row|
          index = scroll_offset + row
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
        surface.draw_text(x + width - 12, y + 4, "^", color: 0x8f7cff) if scroll_offset.positive?
        if scroll_offset + visible_rows < items.length
          surface.draw_text(x + width - 12, y + height - 16, "v", color: 0x8f7cff)
        end
      end

      def handle(event)
        return false unless focused && event.respond_to?(:fetch)
        kind = event.fetch("kind", 0)
        if kind == Input::POINTER_WHEEL
          delta = event.fetch("dy", 0)
          delta = event.fetch("dx", 0) if delta.zero?
          return scroll(delta.positive? ? -3 : 3)
        end
        return false unless kind == Input::KEY_DOWN

        code = event.fetch("code", 0)
        if UP_KEYS.include?(code)
          move(-1)
        elsif DOWN_KEYS.include?(code)
          move(1)
        elsif code == 13
          activate
        elsif code == 8
          (@on_back || @on_cancel)&.call
          invalidate
          true
        elsif code == 27
          @on_cancel&.call
          invalidate
          true
        else
          false
        end
      end

      def handle_pointer(local_x, local_y, _event)
        return false unless contains?(local_x, local_y)

        index = scroll_offset + (local_y - y) / ROW_HEIGHT
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
        @scroll_offset = selected_index if selected_index < scroll_offset
        @scroll_offset = selected_index - visible_rows + 1 if selected_index >= scroll_offset + visible_rows
        @scroll_offset = [@scroll_offset, 0].max
      end

      def scroll(delta)
        maximum = [items.length - visible_rows, 0].max
        previous = scroll_offset
        @scroll_offset = [[scroll_offset + delta, 0].max, maximum].min
        invalidate if previous != scroll_offset
        previous != scroll_offset
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
