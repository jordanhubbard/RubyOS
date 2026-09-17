# frozen_string_literal: true

module RubyOS
  module GUI
    class Element
      attr_accessor :parent, :visible, :enabled

      def initialize(visible: true, enabled: true)
        @visible = visible
        @enabled = enabled
      end

      def invalidate
        node = self
        node = node.parent until node.nil? || node.respond_to?(:dirty=)
        node.dirty = true if node
      end
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
      attr_accessor :text, :color

      def initialize(text, color: 0xffffff, **)
        super(**)
        @text, @color = text, color
      end

      def draw(surface)
        super
        surface.draw_text(x, y, text, color:) if visible
      end
    end

    class Button < Label
      def initialize(text, action: nil, **)
        super(text, **)
        @action = action
      end

      def handle(event)
        return false unless event == :click

        @action&.call(self)
        invalidate
        true
      end
    end

    class TextInput < View
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
        lines = text.split("\n", -1).last([height / 20, 1].max)
        lines.each_with_index { |line, index| surface.draw_text(x + 4, y + 4 + index * 20, line, color: @color) }
        surface.draw_text(x + 4 + lines.last.to_s.each_char.count * 8,
                          y + 4 + (lines.length - 1) * 20, "_", color: 0xffd866)
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

      private

      def insert(value)
        characters = text.each_char.to_a
        inserted = String(value).each_char.to_a
        characters.insert(cursor, *inserted)
        @cursor += inserted.length
        replace(characters.join)
      end
    end
  end
end
