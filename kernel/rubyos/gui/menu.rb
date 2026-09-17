# frozen_string_literal: true

module RubyOS
  module GUI
    MenuItem = Data.define(:label, :action, :enabled, :separator, :shortcut) do
      def self.command(label, shortcut: nil, enabled: true, &action)
        new(label: String(label), action:, enabled:, separator: false, shortcut:)
      end

      def self.separator
        new(label: "", action: nil, enabled: false, separator: true, shortcut: nil)
      end
    end

    Menu = Data.define(:title, :items) do
      def initialize(title:, items:)
        super(title: String(title), items: Array(items).freeze)
      end
    end

    class MenuBar
      HEIGHT = 24
      ROW_HEIGHT = 22
      GLYPH_WIDTH = 8
      PADDING = 8

      attr_reader :menus, :open_index, :hot_index

      def initialize(width:, height:)
        @width = Integer(width)
        @height = Integer(height)
        @menus = []
        dismiss
      end

      def replace(menus)
        @menus = Array(menus)
        dismiss
        self
      end

      def open? = !open_index.nil?

      def dismiss
        @open_index = nil
        @hot_index = nil
        @scroll_offset = 0
        false
      end

      def draw(surface, active_title: nil, status: nil)
        surface.fill_rect(0, 0, @width, HEIGHT, 0x251b31)
        rectangles = title_rects
        rectangles.each_with_index do |(x, width), index|
          surface.fill_rect(x, 0, width, HEIGHT, 0x553184) if index == open_index
          surface.draw_text(x + PADDING, 6, menus.fetch(index).title,
                            color: index == open_index ? 0xffffff : 0xe8dff5)
        end
        menu_end = rectangles.last&.then { |x, width| x + width } || PADDING
        if active_title && menu_end + 16 < @width - 112
          available = [(@width - 120 - menu_end - 16) / GLYPH_WIDTH, 0].max
          surface.draw_text(menu_end + 16, 6, active_title.each_char.first(available).join,
                            color: 0x91869f)
        end
        status_x = [[@width - 104, menu_end + 8].max, @width].min
        status_columns = [(@width - status_x - 4) / GLYPH_WIDTH, 0].max
        if status_columns.positive?
          display_status = String(status || "Ruby 4").each_char.first(status_columns).join
          surface.draw_text(status_x, 6, display_status, color: 0xd8cae5)
        end
        draw_popup(surface) if open?
        self
      end

      def handle(event)
        kind = event.fetch("kind", 0)
        return handle_key(event) if kind == Input::KEY_DOWN && open?
        return handle_wheel(event) if kind == Input::POINTER_WHEEL && open?
        return handle_move(event) if kind == Input::POINTER_MOVE && open?
        return false unless kind == Input::POINTER_DOWN && event.fetch("button", 0) == 1

        x = event.fetch("x", 0)
        y = event.fetch("y", 0)
        if y < HEIGHT
          index = title_rects.index { |left, width| left <= x && x < left + width }
          return false unless index

          open_index == index ? dismiss : open_menu(index)
          return true
        end
        return false unless open?

        index = item_index_at(x, y)
        if index
          activate(index)
        else
          dismiss
        end
        true
      end

      private

      def title_rects
        x = 4
        menus.map do |menu|
          width = menu.title.each_char.count * GLYPH_WIDTH + PADDING * 2
          rect = [x, width]
          x += width
          rect
        end
      end

      def popup_width
        menu = menus.fetch(open_index)
        longest = menu.items.map do |item|
          item.label.each_char.count + (item.shortcut ? item.shortcut.each_char.count + 3 : 0)
        end.max || 1
        [[longest * GLYPH_WIDTH + PADDING * 2, 128].max, @width - 8].min
      end

      def visible_rows
        [(@height - HEIGHT - 8) / ROW_HEIGHT, 1].max
      end

      def popup_rect
        title_x, = title_rects.fetch(open_index)
        width = popup_width
        x = [title_x, @width - width - 4].min
        count = [menus.fetch(open_index).items.length, visible_rows].min
        [x, HEIGHT, width, count * ROW_HEIGHT + 4]
      end

      def draw_popup(surface)
        x, y, width, height = popup_rect
        surface.fill_rect(x + 3, y + 4, width, height, 0x0b0910)
        surface.fill_rect(x, y, width, height, 0x8f63c7)
        surface.fill_rect(x + 2, y + 2, width - 4, height - 4, 0x181522)
        visible_items.each_with_index do |(item, index), row|
          row_y = y + 2 + row * ROW_HEIGHT
          if item.separator
            surface.fill_rect(x + 8, row_y + ROW_HEIGHT / 2, width - 16, 1, 0x493d59)
            next
          end
          surface.fill_rect(x + 3, row_y, width - 6, ROW_HEIGHT, 0x553184) if index == hot_index
          color = item.enabled ? 0xf2eaf7 : 0x746b7c
          surface.draw_text(x + PADDING, row_y + 6, item.label, color:)
          if item.shortcut
            shortcut_x = x + width - PADDING - item.shortcut.each_char.count * GLYPH_WIDTH
            surface.draw_text(shortcut_x, row_y + 6, item.shortcut, color: 0xa99bb8)
          end
        end
        surface.draw_text(x + width - 14, y + 5, "^", color: 0xffd866) if @scroll_offset.positive?
        if @scroll_offset + visible_rows < menus.fetch(open_index).items.length
          surface.draw_text(x + width - 14, y + height - 16, "v", color: 0xffd866)
        end
      end

      def visible_items
        menu = menus.fetch(open_index)
        menu.items.each_with_index.drop(@scroll_offset).first(visible_rows)
      end

      def open_menu(index)
        @open_index = index
        @scroll_offset = 0
        @hot_index = next_enabled(-1, 1)
        true
      end

      def handle_key(event)
        case event.fetch("code", 0)
        when 27
          dismiss
        when 1_073_741_906
          @hot_index = next_enabled(hot_index || 0, -1)
          keep_hot_visible
        when 1_073_741_905
          @hot_index = next_enabled(hot_index || -1, 1)
          keep_hot_visible
        when 1_073_741_904
          open_menu((open_index - 1) % menus.length)
        when 1_073_741_903
          open_menu((open_index + 1) % menus.length)
        when 13
          activate(hot_index) if hot_index
        else
          return false
        end
        true
      end

      def handle_wheel(event)
        delta = event.fetch("dy", 0)
        delta = event.fetch("dx", 0) if delta.zero?
        maximum = [menus.fetch(open_index).items.length - visible_rows, 0].max
        @scroll_offset = [[@scroll_offset + (delta.positive? ? -3 : 3), 0].max, maximum].min
        true
      end

      def handle_move(event)
        index = item_index_at(event.fetch("x", 0), event.fetch("y", 0))
        @hot_index = index if index && selectable?(index)
        true
      end

      def item_index_at(point_x, point_y)
        x, y, width, height = popup_rect
        return nil unless x <= point_x && point_x < x + width && y <= point_y && point_y < y + height

        index = @scroll_offset + (point_y - y - 2) / ROW_HEIGHT
        index if index >= 0 && index < menus.fetch(open_index).items.length
      end

      def selectable?(index)
        item = menus.fetch(open_index).items.fetch(index)
        item.enabled && !item.separator
      end

      def next_enabled(start, delta)
        items = menus.fetch(open_index).items
        return nil if items.empty?
        items.length.times do |step|
          index = (start + delta * (step + 1)) % items.length
          return index if selectable?(index)
        end
        nil
      end

      def keep_hot_visible
        return unless hot_index
        @scroll_offset = hot_index if hot_index < @scroll_offset
        if hot_index >= @scroll_offset + visible_rows
          @scroll_offset = hot_index - visible_rows + 1
        end
      end

      def activate(index)
        return false unless index && selectable?(index)

        action = menus.fetch(open_index).items.fetch(index).action
        dismiss
        action&.call
        true
      end
    end
  end
end
