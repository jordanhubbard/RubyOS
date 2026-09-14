# frozen_string_literal: true

module RubyOS
  module Chipset
    Wait = Data.define(:line)
    Move = Data.define(:register, :value)

    class Playfield
      attr_reader :width, :height, :pixels
      attr_accessor :scroll_x, :scroll_y

      def initialize(width, height, fill: 0)
        @width = Integer(width)
        @height = Integer(height)
        raise ArgumentError, "playfield dimensions must be positive" unless @width.positive? && @height.positive?
        @pixels = Array.new(@width * @height, fill)
        @scroll_x = @scroll_y = 0
      end

      def put(x, y, color)
        pixels[y * width + x] = color & 0xffffff if x.between?(0, width - 1) && y.between?(0, height - 1)
        self
      end

      def get(x, y)
        return 0 unless x.between?(0, width - 1) && y.between?(0, height - 1)
        pixels[y * width + x]
      end

      def sample(x, y)
        get((x + scroll_x) % width, (y + scroll_y) % height)
      end

      def fill(color)
        pixels.fill(color & 0xffffff)
        self
      end
    end

    module Blitter
      module_function

      def fill(destination, x:, y:, width:, height:, color:)
        height.times do |row|
          width.times { |column| destination.put(x + column, y + row, color) }
        end
        destination
      end

      def copy(source, destination, source_x:, source_y:, destination_x:, destination_y:, width:, height:)
        snapshot = height.times.flat_map do |row|
          width.times.map { |column| source.get(source_x + column, source_y + row) }
        end
        snapshot.each_with_index do |color, index|
          destination.put(destination_x + index % width, destination_y + index / width, color)
        end
        destination
      end
    end

    class Copper
      attr_reader :instructions, :warnings

      def initialize(*instructions)
        @instructions = instructions.flatten
        @warnings = []
        @program_counter = 0
      end

      def reset
        @program_counter = 0
      end

      def apply(view, line)
        while (instruction = instructions[@program_counter])
          if instruction.is_a?(Wait)
            break if line < instruction.line
          elsif instruction.is_a?(Move)
            apply_move(view, instruction)
          end
          @program_counter += 1
        end
      end

      private

      def apply_move(view, instruction)
        name = instruction.register.to_s.upcase
        if name.match?(/\ACOLOR\d+\z/)
          index = name.delete_prefix("COLOR").to_i
          view.palette[index] = instruction.value & 0xffffff if index < view.palette.length
        else
          warnings << "unknown register #{name}"
        end
      end
    end

    class Sprite
      attr_accessor :x, :y, :enabled, :key_color
      attr_reader :playfield

      def initialize(playfield, x: 0, y: 0, key_color: 0)
        @playfield = playfield
        @x = x
        @y = y
        @key_color = key_color
        @enabled = true
      end

      def pixel_at(point_x, point_y)
        return nil unless enabled
        color = playfield.get(point_x - x, point_y - y)
        color == key_color ? nil : color
      end
    end

    class View
      attr_reader :width, :height, :playfield, :sprites, :palette
      attr_accessor :copper

      def initialize(width, height)
        @width = width
        @height = height
        @playfield = Playfield.new(width, height)
        @sprites = []
        @palette = Array.new(32, 0)
        @copper = Copper.new
      end

      def pixel_at(x, y)
        sprites.each do |sprite|
          color = sprite.pixel_at(x, y)
          return color if color
        end
        playfield.sample(x, y)
      end

      def raster
        output = []
        copper.reset
        height.times do |y|
          copper.apply(self, y)
          width.times { |x| output << pixel_at(x, y) }
        end
        output
      end
    end
  end
end
