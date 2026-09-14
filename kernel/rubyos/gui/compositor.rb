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

      attr_reader :title
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
        surface.draw_text(x + 10, y + 7, title, color: focused ? 0xffffff : 0xc5bacb)
        surface.fill_rect(x + width - 18, y + 8, 8, 8, focused ? 0xff668a : 0x806774)
        body_y = y + TITLE_HEIGHT
        surface.fill_rect(x + BORDER, body_y, width - BORDER * 2,
                          height - TITLE_HEIGHT - BORDER, background || 0x201a28)
        translated = TranslatedSurface.new(surface, x + 10, body_y + 9)
        children.each { |child| child.draw(translated) if child.visible }
      end

      def close_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_x >= x + width - 24 && point_y < y + TITLE_HEIGHT
      end

      def handle(event)
        if event.fetch("kind", 0) == 4 && event.fetch("button", 0) == 1
          local_x = event.fetch("x") - x - 10
          local_y = event.fetch("y") - y - TITLE_HEIGHT - 9
          child = children.reverse.find { |candidate| candidate.contains?(local_x, local_y) }
          return true if child&.enabled && child.handle(:click)
        end
        children.reverse_each { |child| return true if child.enabled && child.handle(event) }
        false
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

      def handle(event)
        kind = event.fetch("kind", 0)
        return focused_window&.handle(event) || false if kind == 1 || kind == 2
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
        return false unless window
        if window.close_hit?(point_x, point_y)
          close(window)
        else
          focus(window)
          window.handle(event)
        end
        true
      end

      def draw(surface, uptime: nil)
        surface.fill_rect(0, 0, width, height, 0x171321)
        surface.fill_rect(0, 0, width, MENU_HEIGHT, 0x2a1f35)
        surface.draw_text(10, 6, @title, color: 0xffd866)
        surface.draw_text(width - 104, 6, uptime || "Ruby 4", color: 0xd8cae5)
        windows.each { |window| window.draw(surface) }
        draw_dock(surface)
        self
      end

      private

      def draw_dock(surface)
        y = height - DOCK_HEIGHT
        surface.fill_rect(0, y, width, DOCK_HEIGHT, 0x241a2d)
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
