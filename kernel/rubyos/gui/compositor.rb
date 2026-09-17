# frozen_string_literal: true

module RubyOS
  module GUI
    class TranslatedSurface
      def initialize(surface, offset_x, offset_y)
        @surface = surface
        @offset_x = offset_x
        @offset_y = offset_y
      end

      def fill_rect(x, y, width, height, color)
        @surface.fill_rect(x + @offset_x, y + @offset_y, width, height, color)
      end

      def draw_text(x, y, text, **options)
        @surface.draw_text(x + @offset_x, y + @offset_y, text, **options)
      end
    end

    class Window < Container
      TITLE_HEIGHT = 24
      BORDER = 2

      attr_accessor :title
      attr_reader :focused_child
      attr_accessor :focused, :minimized

      def initialize(title, **options)
        super(**options)
        @title = String(title)
        @focused = false
        @minimized = false
      end

      def draw(surface)
        return unless visible && !minimized
        surface.fill_rect(x + 4, y + 5, width, height, 0x0b0910)
        surface.fill_rect(x, y, width, height, focused ? 0x9b6dff : 0x655b70)
        surface.fill_rect(x + BORDER, y + BORDER, width - BORDER * 2,
                          TITLE_HEIGHT - BORDER, focused ? 0x553184 : 0x393140)
        display_title = title.each_char.first([(width - 72) / 8, 1].max).join
        surface.draw_text(x + 10, y + 7, display_title, color: focused ? 0xffffff : 0xc5bacb)
        surface.fill_rect(x + width - 38, y + 10, 8, 3, focused ? 0xd8cae5 : 0x806774)
        surface.fill_rect(x + width - 18, y + 8, 8, 8, focused ? 0xff668a : 0x806774)
        body_y = y + TITLE_HEIGHT
        surface.fill_rect(x + BORDER, body_y, width - BORDER * 2,
                          height - TITLE_HEIGHT - BORDER, background || 0x201a28)
        translated = TranslatedSurface.new(surface, x + 10, body_y + 9)
        children.each { |child| child.draw(translated) if child.visible }
      end

      def add(child)
        result = super
        focus_child(child) if focused_child.nil? && child.focusable?
        result
      end

      def close_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_x >= x + width - 24 && point_y < y + TITLE_HEIGHT
      end

      def minimize_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_x >= x + width - 44 &&
          point_x < x + width - 24 && point_y < y + TITLE_HEIGHT
      end

      def title_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_y < y + TITLE_HEIGHT
      end

      def handle(event)
        if event.fetch("kind", 0) == 4 && event.fetch("button", 0) == 1
          local_x = event.fetch("x") - x - 10
          local_y = event.fetch("y") - y - TITLE_HEIGHT - 9
          child = children.reverse.find { |candidate| candidate.contains?(local_x, local_y) }
          if child&.enabled
            focus_child(child) if child.focusable?
            return child.handle_pointer(local_x, local_y, event) if child.respond_to?(:handle_pointer)
            return child.handle(:click) if child.is_a?(Button)
          end
        end
        if event.fetch("kind", 0) == 1 && event.fetch("code", 0) == 9
          cycle_focus
          return true
        end
        return true if focused_child&.enabled && focused_child.handle(event)
        false
      end

      def focus_child(child)
        return unless child&.focusable? && children.include?(child)

        children.each { |candidate| candidate.focused = false }
        @focused_child = child
        child.focused = true
        invalidate
        child
      end

      private

      def cycle_focus
        candidates = children.select { |child| child.visible && child.enabled && child.focusable? }
        return if candidates.empty?

        index = focused_child ? candidates.index(focused_child) : nil
        focus_child(candidates.fetch(index ? (index + 1) % candidates.length : 0))
      end
    end

    class Compositor
      MENU_HEIGHT = 24
      DOCK_HEIGHT = 42

      attr_reader :width, :height, :windows

      def initialize(width:, height:, title: "RubyOS")
        @width = width
        @height = height
        @title = title
        @windows = []
        @dock_items = []
        @shortcuts = []
        @dragging = nil
      end

      def add_window(window)
        windows << window
        focus(window)
        window
      end

      def close(window)
        windows.delete(window)
        focus(windows.last) if windows.any?
        window
      end

      def focus(window)
        return unless windows.include?(window)
        windows.each { |candidate| candidate.focused = false }
        windows.delete(window)
        windows << window
        window.focused = true
        window
      end

      def focused_window
        windows.reverse.find { |window| !window.minimized }
      end

      def window_at(point_x, point_y)
        windows.reverse.find do |window|
          window.visible && !window.minimized && window.contains?(point_x, point_y)
        end
      end

      def add_dock_item(label, &action)
        @dock_items << [String(label), action]
        self
      end

      def add_shortcut(label, x:, y:, &action)
        @shortcuts << [String(label), Integer(x), Integer(y), action]
        self
      end

      def handle(event)
        kind = event.fetch("kind", 0)
        return focused_window&.handle(event) || false if kind == 1 || kind == 2
        if kind == 3 && @dragging
          window, offset_x, offset_y = @dragging
          window.x = [[event.fetch("x") - offset_x, 0].max, width - window.width].min
          window.y = [[event.fetch("y") - offset_y, MENU_HEIGHT].max,
                      height - DOCK_HEIGHT - Window::TITLE_HEIGHT].min
          return true
        end
        if kind == 5 && @dragging
          @dragging = nil
          return true
        end
        return false unless kind == 4 && event.fetch("button", 0) == 1
        point_x = event.fetch("x")
        point_y = event.fetch("y")
        if point_y >= height - DOCK_HEIGHT
          index = (point_x - 12) / dock_slot_width
          item = @dock_items[index] if index >= 0
          item&.last&.call
          return !item.nil?
        end
        window = window_at(point_x, point_y)
        unless window
          shortcut = @shortcuts.find do |_label, x, y, _action|
            x <= point_x && point_x < x + 48 && y <= point_y && point_y < y + 48
          end
          shortcut&.last&.call
          return !shortcut.nil?
        end
        if window.close_hit?(point_x, point_y)
          close(window)
        elsif window.minimize_hit?(point_x, point_y)
          window.minimized = true
          focus(windows.reverse.find { |candidate| !candidate.minimized })
        else
          focus(window)
          @dragging = [window, point_x - window.x, point_y - window.y] if window.title_hit?(point_x, point_y)
          window.handle(event)
        end
        true
      end

      def draw(surface, uptime: nil)
        surface.fill_rect(0, 0, width, height, 0x171321)
        draw_wallpaper(surface)
        surface.fill_rect(0, 0, width, MENU_HEIGHT, 0x2a1f35)
        surface.draw_text(10, 6, @title, color: 0xffd866)
        if focused_window
          surface.draw_text(88, 6, focused_window.title.each_char.first(32).join, color: 0xa99bb8)
        end
        surface.draw_text(width - 104, 6, uptime || "Ruby 4", color: 0xd8cae5)
        windows.each { |window| window.draw(surface) }
        draw_dock(surface)
        self
      end

      private

      def draw_wallpaper(surface)
        surface.fill_rect(0, MENU_HEIGHT, width, height - MENU_HEIGHT, 0x191624)
        MENU_HEIGHT.step(height - DOCK_HEIGHT, 48) do |row|
          surface.fill_rect(0, row, width, 1, 0x211c30)
        end
        0.step(width - 1, 48) { |column| surface.fill_rect(column, MENU_HEIGHT, 1, height, 0x1e1a2b) }
        @shortcuts.each do |label, x, y, _action|
          surface.fill_rect(x + 8, y, 28, 28, 0x553184)
          surface.draw_text(x, y + 34, label, color: 0xe8dff5)
        end
      end

      def draw_dock(surface)
        y = height - DOCK_HEIGHT
        surface.fill_rect(0, y, width, DOCK_HEIGHT, 0x17131d)
        surface.fill_rect(0, y, width, 2, 0x49325f)
        @dock_items.each_with_index do |(label, _), index|
          x = 12 + index * dock_slot_width
          surface.fill_rect(x, y + 6, dock_slot_width - 8, 28, 0x49325f)
          surface.draw_text(x + 7, y + 14, label, color: 0xf2eaf7)
        end
      end


      def dock_slot_width
        [(@width - 24) / [@dock_items.length, 1].max, 40].max
      end
    end
  end
end
