# frozen_string_literal: true

module RubyOS
  module Games
    class Invaders
      attr_reader :player_x, :enemies, :shot, :score, :sound_events

      def initialize
        @player_x = 15
        @enemies = [4, 10, 16, 22, 28].product([3, 6])
        @shot = nil
        @score = 0
        @direction = 1
        @sound_events = []
      end

      def handle(event)
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN

        case event.fetch("code", 0)
        when 97 then @player_x = [player_x - 1, 0].max
        when 100 then @player_x = [player_x + 1, 29].min
        when 32 then fire
        else return false
        end
        true
      end

      def fire
        unless shot
          @shot = [player_x + 1, 17]
          sound_events << :fire
        end
        self
      end

      def tick
        if enemies.any?
          edge = enemies.any? { |x, _| (@direction.positive? && x >= 29) || (@direction.negative? && x <= 0) }
          if edge
            @direction = -@direction
            enemies.each { |enemy| enemy[1] += 1 }
          else
            enemies.each { |enemy| enemy[0] += @direction }
          end
        end
        if shot
          shot[1] -= 1
          target = enemies.find { |x, y| x == shot[0] && y == shot[1] }
          if target
            enemies.delete(target)
            @score += 100
            sound_events << :hit
            @shot = nil
          elsif shot[1].negative?
            @shot = nil
          end
        end
        self
      end

      def view
        display = Chipset::View.new(32, 20, mode: Chipset::MODE_INDEXED)
        display.palette[1] = 0x89ddff
        display.palette[2] = 0xffd866
        display.palette[3] = 0xff668a
        enemies.each { |x, y| Chipset::Blitter.fill(display.pf0, x:, y:, width: 2, height: 1, color: 1) }
        Chipset::Blitter.fill(display.pf0, x: player_x, y: 18, width: 3, height: 1, color: 2)
        display.pf0.put(*shot, 3) if shot
        display
      end

      def cue
        event = sound_events.shift
        return nil unless event

        amplitude = event == :hit ? 8_000 : 4_000
        Sound::PCM.new(Array.new(96) { |index| index.even? ? amplitude : -amplitude })
      end
    end

    class Snake
      DIRECTIONS = { 97 => [-1, 0], 100 => [1, 0], 119 => [0, -1], 115 => [0, 1] }.freeze
      attr_reader :body, :food, :score, :direction

      def initialize
        @body = [[8, 8], [7, 8], [6, 8]]
        @food = [14, 8]
        @direction = [1, 0]
        @score = 0
        @finished = false
      end

      def handle(event)
        proposed = DIRECTIONS[event.fetch("code", 0)]
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN && proposed
        return false if proposed[0] == -direction[0] && proposed[1] == -direction[1]

        @direction = proposed
        true
      end

      def tick
        return self if finished?

        head = [(body.first[0] + direction[0]) % 32, (body.first[1] + direction[1]) % 20]
        if body.include?(head)
          @finished = true
          return self
        end
        body.unshift(head)
        if head == food
          @score += 10
          @food = [(@food[0] + 11) % 32, (@food[1] + 7) % 20]
        else
          body.pop
        end
        self
      end

      def finished? = @finished

      def view
        display = Chipset::View.new(32, 20, mode: Chipset::MODE_INDEXED)
        display.palette[1] = 0xc3e88d
        display.palette[2] = 0xff668a
        body.each { |x, y| display.pf0.put(x, y, 1) }
        display.pf0.put(*food, 2)
        display
      end
    end
  end

  module Apps
    class ArcadeView < GUI::View
      def initialize(game, scale: 4, **options)
        super(**options)
        @game = game
        @scale = scale
      end

      def handle(event)
        handled = @game.handle(event)
        invalidate if handled
        handled
      end

      def draw(surface)
        view = @game.view
        view.raster.each_with_index do |color, index|
          surface.fill_rect(x + (index % view.width) * @scale,
                            y + (index / view.width) * @scale,
                            @scale, @scale, color)
        end
      end
    end

    class Invaders < Application
      attr_reader :game

      def initialize(**options)
        super
        @game = Games::Invaders.new
      end

      def build_window
        GUI::Window.new("Ruby Invaders", x: 72, y: 44, width: 164, height: 126,
                        background: 0x080b18).tap do |window|
          window.add(ArcadeView.new(game, x: 0, y: 0, width: 128, height: 80))
          window.add(GUI::Label.new("A/D move  Space fire", x: 0, y: 84, color: 0xffd866))
        end
      end
    end

    class Snake < Application
      attr_reader :game

      def initialize(**options)
        super
        @game = Games::Snake.new
      end

      def build_window
        GUI::Window.new("Ruby Snake", x: 242, y: 70, width: 164, height: 126,
                        background: 0x08140e).tap do |window|
          window.add(ArcadeView.new(game, x: 0, y: 0, width: 128, height: 80))
          window.add(GUI::Label.new("W/A/S/D steer", x: 0, y: 84, color: 0xc3e88d))
        end
      end
    end
  end
end
