# frozen_string_literal: true

# Public application toolkit.  Application code targets Canvas, Input and Audio;
# the runtime decides whether frames stay in memory, are copied to a native
# surface, or are presented by RemoteOS-SDL.
module RubyOS
  module App
    class Canvas
      attr_reader :bitmap

      def initialize(width:, height:, background: 0)
        @bitmap = Media::Bitmap.new(width, height, background:)
      end

      def width = bitmap.width
      def height = bitmap.height
      def clear(color = 0)
        bitmap.clear(color)
        self
      end
      def pixel(x, y, color:)
        bitmap.put(Integer(x), Integer(y), Integer(color))
        self
      end
      def rect(x, y, width, height, color:)
        bitmap.rect(x, y, width, height, color:)
        self
      end
      def line(x0, y0, x1, y1, color:)
        bitmap.line(x0, y0, x1, y1, color:)
        self
      end
      def sprite(image, x:, y:, transparent: nil)
        bitmap.blit(image, x, y, key: transparent)
        self
      end

      def frame(x, y, width, height, color:)
        line(x, y, x + width - 1, y, color:)
        line(x, y + height - 1, x + width - 1, y + height - 1, color:)
        line(x, y, x, y + height - 1, color:)
        line(x + width - 1, y, x + width - 1, y + height - 1, color:)
        self
      end

      # Portable block text deliberately lives in Ruby. Remote SDL is an
      # optional accelerator, not a requirement for application correctness.
      def text(x, y, value, color: 0xffffff, scale: 1)
        cursor = Integer(x)
        String(value).upcase.each_char do |character|
          glyph = FONT.fetch(character, FONT.fetch("?"))
          glyph.each_with_index do |row, row_index|
            5.times do |column|
              next if (row & (1 << (4 - column))).zero?
              rect(cursor + column * scale, Integer(y) + row_index * scale,
                   scale, scale, color:)
            end
          end
          cursor += 6 * scale
        end
        self
      end

      FONT = {
        " " => [0, 0, 0, 0, 0, 0, 0], "?" => [14, 17, 1, 2, 4, 0, 4],
        "A" => [14, 17, 17, 31, 17, 17, 17], "B" => [30, 17, 17, 30, 17, 17, 30],
        "C" => [14, 17, 16, 16, 16, 17, 14], "D" => [30, 17, 17, 17, 17, 17, 30],
        "E" => [31, 16, 16, 30, 16, 16, 31], "F" => [31, 16, 16, 30, 16, 16, 16],
        "G" => [14, 17, 16, 23, 17, 17, 14], "H" => [17, 17, 17, 31, 17, 17, 17],
        "I" => [31, 4, 4, 4, 4, 4, 31], "J" => [7, 2, 2, 2, 18, 18, 12],
        "K" => [17, 18, 20, 24, 20, 18, 17], "L" => [16, 16, 16, 16, 16, 16, 31],
        "M" => [17, 27, 21, 21, 17, 17, 17], "N" => [17, 25, 21, 19, 17, 17, 17],
        "O" => [14, 17, 17, 17, 17, 17, 14], "P" => [30, 17, 17, 30, 16, 16, 16],
        "Q" => [14, 17, 17, 17, 21, 18, 13], "R" => [30, 17, 17, 30, 20, 18, 17],
        "S" => [15, 16, 16, 14, 1, 1, 30], "T" => [31, 4, 4, 4, 4, 4, 4],
        "U" => [17, 17, 17, 17, 17, 17, 14], "V" => [17, 17, 17, 17, 17, 10, 4],
        "W" => [17, 17, 17, 21, 21, 21, 10], "X" => [17, 17, 10, 4, 10, 17, 17],
        "Y" => [17, 17, 10, 4, 4, 4, 4], "Z" => [31, 1, 2, 4, 8, 16, 31],
        "0" => [14, 17, 19, 21, 25, 17, 14], "1" => [4, 12, 4, 4, 4, 4, 14],
        "2" => [14, 17, 1, 2, 4, 8, 31], "3" => [30, 1, 1, 14, 1, 1, 30],
        "4" => [2, 6, 10, 18, 31, 2, 2], "5" => [31, 16, 16, 30, 1, 1, 30],
        "6" => [14, 16, 16, 30, 17, 17, 14], "7" => [31, 1, 2, 4, 8, 8, 8],
        "8" => [14, 17, 17, 14, 17, 17, 14], "9" => [14, 17, 17, 15, 1, 1, 14],
        ":" => [0, 4, 4, 0, 4, 4, 0], "-" => [0, 0, 0, 31, 0, 0, 0],
        "." => [0, 0, 0, 0, 0, 12, 12], "/" => [1, 2, 2, 4, 8, 8, 16]
      }.freeze
    end

    class Audio
      attr_reader :output

      def initialize(output = nil)
        @output = output
      end

      def available? = !output.nil?
      def play(pcm)
        output&.play(pcm)
        pcm
      end
      def tone(frequency, duration_ms: 100, waveform: :sine, amplitude: 0.2)
        play(Sound::Waveform.public_send(waveform, frequency, duration_ms:, amplitude:))
      end
    end

    module Backend
      class Memory
        attr_reader :last_frame, :frames
        def initialize = (@frames = 0)
        def present(bitmap)
          @last_frame = bitmap
          @frames += 1
          self
        end
        def close = self
      end

      class Surface
        attr_reader :surface, :presenter
        def initialize(surface, presenter: nil)
          @surface, @presenter = surface, presenter
        end
        def present(bitmap)
          surface.upload(bitmap.bytes)
          presenter&.call
          self
        end
        def close = self
      end

      class RemoteSDL < Surface
        attr_reader :desktop
        def initialize(client, width:, height:, title: "RubyOS Application")
          @desktop = Bridge::RemoteDesktop.new(client, width:, height:, title:)
          super(desktop.surface, presenter: -> { desktop.present })
        end
        def events = desktop.events
        def close = desktop.close
      end
    end

    class Base
      attr_reader :canvas, :audio
      def initialize(width: 640, height: 400, audio: Audio.new)
        @canvas = Canvas.new(width:, height:)
        @audio = audio
      end
      def start; end
      def update(_seconds); end
      def input(_event); end
      def draw(_canvas); end
      def stop; end
    end

    class Runtime
      attr_reader :application, :backend
      def initialize(application, backend: Backend::Memory.new)
        @application, @backend = application, backend
      end
      def frame(seconds: 1.0 / 60)
        application.update(Float(seconds))
        application.draw(application.canvas)
        backend.present(application.canvas.bitmap)
        self
      end
      def dispatch(event)
        application.input(event)
        self
      end
      def run(frames:, seconds: 1.0 / 60)
        application.start
        Integer(frames).times { frame(seconds:) }
        self
      ensure
        application.stop
      end
      def close
        backend.close
        self
      end
    end
  end
end
