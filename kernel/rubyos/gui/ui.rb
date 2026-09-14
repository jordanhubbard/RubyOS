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
  end
end
