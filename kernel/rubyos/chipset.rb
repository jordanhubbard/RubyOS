# frozen_string_literal: true

module RubyOS
  module Chipset
    MODE_DIRECT = :direct
    MODE_INDEXED = :indexed
    BPLCON_PF1_KEY = 1
    Wait = Data.define(:line)
    Move = Data.define(:register, :value)

    class Playfield
      attr_reader :width, :height, :pixels, :mode
      attr_accessor :scroll_x, :scroll_y

      def initialize(width, height, fill: 0, mode: MODE_DIRECT)
        @width = Integer(width)
        @height = Integer(height)
        raise ArgumentError, "playfield dimensions must be positive" unless @width.positive? && @height.positive?
        raise ArgumentError, "unknown playfield mode" unless [MODE_DIRECT, MODE_INDEXED].include?(mode)
        @mode = mode
        @pixels = Array.new(@width * @height, normalize(fill))
        @scroll_x = @scroll_y = 0
      end

      def put(x, y, color)
        pixels[y * width + x] = normalize(color) if x.between?(0, width - 1) && y.between?(0, height - 1)
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
        pixels.fill(normalize(color))
        self
      end

      private

      def normalize(color) = Integer(color) & (mode == MODE_INDEXED ? 0xff : 0xffffff)
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

      def cookie(source, mask, destination, source_x:, source_y:, destination_x:, destination_y:,
                 width:, height:)
        height.times do |row|
          width.times do |column|
            next if mask.get(source_x + column, source_y + row).zero?

            destination.put(destination_x + column, destination_y + row,
                            source.get(source_x + column, source_y + row))
          end
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
        elsif name == "BPLCON"
          view.bplcon = instruction.value
        elsif name == "KEY_COLOR"
          view.key_color = instruction.value
        elsif name == "DIWSTART"
          view.diw_start = instruction.value
        elsif name == "DIWSTOP"
          view.diw_stop = instruction.value
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
      attr_reader :width, :height, :playfield, :pf0, :pf1, :sprites, :palette, :scale
      attr_accessor :copper
      attr_accessor :bplcon, :key_color, :diw_start, :diw_stop

      def initialize(width, height, mode: MODE_DIRECT, scale: 1)
        @width = width
        @height = height
        @scale = [Integer(scale), 1].max
        @pf0 = Playfield.new(width, height, mode:)
        @pf1 = Playfield.new(width, height, mode:)
        @playfield = @pf0
        @sprites = []
        @palette = Array.new(32, 0)
        @copper = Copper.new
        @bplcon = 0
        @key_color = 0
        @diw_start = 0
        @diw_stop = height - 1
      end

      def pixel_at(x, y)
        return 0 unless y.between?(diw_start, diw_stop)

        sprites.each do |sprite|
          color = sprite.pixel_at(x, y)
          return resolve(color, sprite.playfield) if color
        end

        base = resolve(pf0.sample(x, y))
        overlay = pf1.sample(x, y)
        keyed = if (bplcon & BPLCON_PF1_KEY) != 0
                  overlay == (pf1.mode == MODE_INDEXED ? key_color & 0xff : key_color & 0xffffff)
                else
                  overlay.zero?
                end
        keyed ? base : resolve(overlay, pf1)
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

      private

      def resolve(color, field = pf0)
        field.mode == MODE_INDEXED ? palette.fetch(color, 0) & 0xffffff : color
      end
    end

    class PaulaChannel
      attr_accessor :samples, :rate, :volume, :pan, :looping

      def initialize
        @samples = []
        @rate = 22_050
        @volume = 64
        @pan = 128
        @looping = false
        @playing = false
        @position = 0.0
      end

      def play
        @position = 0.0
        @playing = true
      end

      def stop = (@playing = false)
      def playing? = @playing
      def position = @position

      def position=(value)
        @position = value
      end
    end

    class Paula
      OUTPUT_RATE = 48_000
      attr_reader :channels

      def initialize
        @channels = Array.new(4) { PaulaChannel.new }
      end

      def mix(frames)
        left = Array.new(frames, 0)
        right = Array.new(frames, 0)
        channels.each do |channel|
          next unless channel.playing? && !channel.samples.empty?

          frames.times do |index|
            position = channel.position.to_i
            if position >= channel.samples.length
              if channel.looping
                channel.position = 0.0
                position = 0
              else
                channel.stop
                break
              end
            end
            sample = channel.samples[position]
            volume = [[channel.volume, 64].min, 0].max / 64.0
            pan = [[channel.pan, 255].min, 0].max
            left[index] += (sample * volume * (255 - pan) / 255.0).to_i
            right[index] += (sample * volume * pan / 255.0).to_i
            channel.position += channel.rate.to_f / OUTPUT_RATE
          end
        end
        frames.times.flat_map do |index|
          [[[left[index], 32_767].min, -32_768].max,
           [[right[index], 32_767].min, -32_768].max]
        end.pack("s<*")
      end
    end

    module Toaster
      module_function

      def wipe_step(view, elapsed, duration)
        fraction = duration <= 0 ? 1.0 : [[Float(elapsed) / duration, 1.0].min, 0.0].max
        view.diw_start = 0
        view.diw_stop = (fraction * (view.height - 1)).to_i
        view
      end
    end

    class Engine
      attr_reader :active_view, :ticks, :paula

      def initialize(paula: Paula.new, &present)
        @paula = paula
        @present = present
        @ticks = 0
        @running = false
      end

      def load_view(view)
        raise ArgumentError, "load_view requires a View" unless view.is_a?(View)

        @active_view = view
        self
      end

      def start = (@running = true)
      def stop = (@running = false)
      def running? = @running

      def tick
        return false unless running? && active_view

        @ticks += 1
        frame = active_view.raster
        audio = paula.mix(Paula::OUTPUT_RATE / 30)
        @present&.call(frame, audio)
        [frame, audio]
      end
    end
  end
end
