# frozen_string_literal: true

module RubyOS
  module Games
    LEFT_KEY = GUI::TextInput::LEFT_KEY
    RIGHT_KEY = GUI::TextInput::RIGHT_KEY
    UP_KEY = GUI::TextInput::UP_KEY
    DOWN_KEY = GUI::TextInput::DOWN_KEY

    module SoundEvents
      attr_reader :sound_events

      def emit_sound(name)
        @sound_events ||= []
        @sound_events << name
      end

      def cue
        name = sound_events&.shift
        return nil unless name

        frequency, duration, waveform, amplitude = {
          start: [392, 120, :triangle, 0.12], move: [180, 24, :sine, 0.05],
          fire: [880, 70, :square, 0.14], hit: [140, 110, :square, 0.18],
          collect: [660, 65, :sine, 0.13], danger: [110, 160, :triangle, 0.16],
          rescue: [988, 140, :sine, 0.14], bomb: [55, 240, :square, 0.20],
          game_over: [82, 320, :triangle, 0.18]
        }.fetch(name, [440, 60, :sine, 0.10])
        Sound::Waveform.public_send(waveform, frequency, duration_ms: duration,
                                    amplitude:)
      end
    end

    class Invaders
      include SoundEvents
      attr_reader :player_x, :enemies, :shot, :score, :sound_events

      def initialize
        @player_x = 15
        @enemies = [4, 10, 16, 22, 28].product([3, 6])
        @shot = nil
        @score = 0
        @direction = 1
        @sound_events = [:start]
        @bitmap = Media::Bitmap.new(32, 20)
        render
      end

      def handle(event)
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN

        case event.fetch("code", 0)
        when 97, LEFT_KEY then @player_x = [player_x - 1, 0].max
        when 100, RIGHT_KEY then @player_x = [player_x + 1, 29].min
        when 32 then fire
        else return false
        end
        render
        true
      end

      def fire
        unless shot
          @shot = [player_x + 1, 17]
          emit_sound(:fire)
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
            emit_sound(:hit)
            @shot = nil
          elsif shot[1].negative?
            @shot = nil
          end
        end
        render
        self
      end

      def view = @bitmap
      def status = "SCORE #{score}  |  #{enemies.length} INVADERS"

      private

      def render
        @bitmap.clear(0x02050d)
        enemies.each { |x, y| @bitmap.rect(x, y, 2, 1, color: 0x89ddff) }
        @bitmap.rect(player_x, 18, 3, 1, color: 0xffd866)
        @bitmap.put(*shot, 0xff668a) if shot
      end
    end

    class Snake
      include SoundEvents
      DIRECTIONS = { 97 => [-1, 0], 100 => [1, 0], 119 => [0, -1], 115 => [0, 1] }.freeze
      attr_reader :body, :food, :score, :direction

      def initialize
        @body = [[8, 8], [7, 8], [6, 8]]
        @food = [14, 8]
        @direction = [1, 0]
        @score = 0
        @finished = false
        @sound_events = [:start]
        @bitmap = Media::Bitmap.new(32, 20)
        render
      end

      def handle(event)
        proposed = DIRECTIONS[event.fetch("code", 0)]
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN && proposed
        return false if proposed[0] == -direction[0] && proposed[1] == -direction[1]

        @direction = proposed
        render
        true
      end

      def tick
        return self if finished?

        head = [(body.first[0] + direction[0]) % 32, (body.first[1] + direction[1]) % 20]
        if body.include?(head)
          @finished = true
          emit_sound(:game_over)
          render
          return self
        end
        body.unshift(head)
        if head == food
          @score += 10
          emit_sound(:collect)
          @food = [(@food[0] + 11) % 32, (@food[1] + 7) % 20]
        else
          body.pop
        end
        render
        self
      end

      def finished? = @finished

      def view = @bitmap
      def status = finished? ? "GAME OVER  |  SCORE #{score}" : "SCORE #{score}  |  LENGTH #{body.length}"

      private

      def render
        @bitmap.clear(0x031009)
        body.each { |x, y| @bitmap.put(x, y, 0xc3e88d) }
        @bitmap.put(*food, 0xff668a)
      end
    end

    class Maze
      include SoundEvents
      Ghost = Data.define(:x, :y, :color)
      WIDTH = 24
      HEIGHT = 15
      DIRECTIONS = {
        97 => [-1, 0], 100 => [1, 0], 119 => [0, -1], 115 => [0, 1],
        LEFT_KEY => [-1, 0], RIGHT_KEY => [1, 0], UP_KEY => [0, -1], DOWN_KEY => [0, 1]
      }.freeze

      attr_reader :player, :ghosts, :pellets, :score, :lives

      def initialize
        @bitmap = Media::Bitmap.new(WIDTH, HEIGHT)
        @score = 0
        @lives = 3
        @direction = [1, 0]
        @desired = @direction
        @sound_events = [:start]
        build_level
        render
      end

      def handle(event)
        proposed = DIRECTIONS[event.fetch("code", 0)]
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN && proposed

        @desired = proposed
        true
      end

      def tick
        @direction = @desired if open?(*step(player, @desired))
        destination = step(player, @direction)
        @player = destination if open?(*destination)
        if pellets.delete(player)
          @score += 10
          emit_sound(:collect) if (@score % 50).zero?
          @score += 250 if pellets.empty?
        end
        @ghosts = ghosts.each_with_index.map { |ghost, index| move_ghost(ghost, index) }
        lose_life if ghosts.any? { |ghost| [ghost.x, ghost.y] == player }
        build_level if pellets.empty?
        render
        self
      end

      def view = @bitmap
      def status = "SCORE #{score}  |  LIVES #{lives}  |  GEMS #{pellets.length}"

      private

      def build_level
        @player = [1, 1]
        @ghosts = [Ghost.new(x: WIDTH - 2, y: 1, color: 0xff668a),
                   Ghost.new(x: WIDTH - 2, y: HEIGHT - 2, color: 0x78dce8)]
        @pellets = {}
        HEIGHT.times do |y|
          WIDTH.times do |x|
            point = [x, y]
            @pellets[point] = true if open?(x, y) && point != player &&
                                      ghosts.none? { |ghost| [ghost.x, ghost.y] == point }
          end
        end
      end

      def wall?(x, y)
        return true if x.zero? || y.zero? || x == WIDTH - 1 || y == HEIGHT - 1
        return true if [6, 17].include?(x) && ![2, 7, 12].include?(y)
        return true if [4, 10].include?(y) && ![3, 11, 20].include?(x)

        false
      end

      def open?(x, y) = !wall?(x, y)
      def step(point, direction) = [point[0] + direction[0], point[1] + direction[1]]

      def move_ghost(ghost, index)
        choices = DIRECTIONS.values.uniq.filter_map do |direction|
          destination = [ghost.x + direction[0], ghost.y + direction[1]]
          destination if open?(*destination)
        end
        target = choices.min_by do |x, y|
          (x - player[0]).abs + (y - player[1]).abs + ((x + y + index) % 3)
        end
        Ghost.new(x: target[0], y: target[1], color: ghost.color)
      end

      def lose_life
        @lives -= 1
        emit_sound(@lives.positive? ? :danger : :game_over)
        @player = [1, 1]
        @ghosts = [Ghost.new(x: WIDTH - 2, y: 1, color: 0xff668a),
                   Ghost.new(x: WIDTH - 2, y: HEIGHT - 2, color: 0x78dce8)]
      end

      def render
        @bitmap.clear(0x03040d)
        HEIGHT.times do |y|
          WIDTH.times { |x| @bitmap.put(x, y, 0x273a9b) if wall?(x, y) }
        end
        pellets.each_key { |x, y| @bitmap.put(x, y, 0xffd866) }
        ghosts.each { |ghost| @bitmap.put(ghost.x, ghost.y, ghost.color) }
        @bitmap.put(*player, 0xffff80)
      end
    end

    class Raiders
      include SoundEvents
      Raider = Data.define(:x, :y, :home_x, :home_y, :diving)
      WIDTH = 32
      HEIGHT = 20

      attr_reader :player_x, :enemies, :shot, :score, :frame

      def initialize
        @bitmap = Media::Bitmap.new(WIDTH, HEIGHT)
        @player_x = 15
        @enemies = 6.times.flat_map do |column|
          3.times.map do |row|
            Raider.new(x: 4 + column * 4, y: 3 + row * 2,
                       home_x: 4 + column * 4, home_y: 3 + row * 2, diving: false)
          end
        end
        @shot = nil
        @score = 0
        @frame = 0
        @direction = 1
        @sound_events = [:start]
        render
      end

      def handle(event)
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN

        case event.fetch("code", 0)
        when 97, LEFT_KEY then @player_x = [player_x - 1, 0].max
        when 100, RIGHT_KEY then @player_x = [player_x + 1, WIDTH - 2].min
        when 32
          unless @shot
            @shot = [player_x, HEIGHT - 3]
            emit_sound(:fire)
          end
        else return false
        end
        render
        true
      end

      def fire
        unless @shot
          @shot = [player_x, HEIGHT - 3]
          emit_sound(:fire)
        end
        render
        self
      end

      def tick
        @frame += 1
        @direction *= -1 if enemies.any? { |enemy| !enemy.diving &&
          ((@direction.positive? && enemy.x >= WIDTH - 2) || (@direction.negative? && enemy.x <= 1)) }
        launch_index = frame % 90 == 0 ? (frame / 90) % [enemies.length, 1].max : nil
        @enemies = enemies.each_with_index.map do |enemy, index|
          diving = enemy.diving || index == launch_index
          if diving
            next_y = enemy.y + 1
            if next_y >= HEIGHT - 1
              next Raider.new(x: enemy.home_x, y: enemy.home_y,
                              home_x: enemy.home_x, home_y: enemy.home_y, diving: false)
            end
            next Raider.new(x: enemy.x + (player_x <=> enemy.x), y: next_y,
                            home_x: enemy.home_x, home_y: enemy.home_y, diving: true)
          end
          Raider.new(x: enemy.x + @direction, y: enemy.y,
                     home_x: enemy.home_x, home_y: enemy.home_y, diving: false)
        end
        update_shot
        render
        self
      end

      def view = @bitmap
      def status = "SCORE #{score}  |  RAIDERS #{enemies.length}"

      private

      def update_shot
        return unless shot

        @shot[1] -= 1
        target = enemies.find { |enemy| enemy.x == shot[0] && enemy.y == shot[1] }
        if target
          enemies.delete(target)
          @score += target.diving ? 200 : 100
          emit_sound(:hit)
          @shot = nil
        elsif shot[1].negative?
          @shot = nil
        end
      end

      def render
        @bitmap.clear(0x02040c)
        enemies.each do |enemy|
          color = enemy.diving ? 0xff668a : 0x51d6c5
          @bitmap.rect(enemy.x, enemy.y, 2, 1, color:)
        end
        @bitmap.rect(player_x - 1, HEIGHT - 2, 3, 1, color: 0xffd866)
        @bitmap.put(*shot, 0xffffff) if shot
      end
    end

    class Defender
      include SoundEvents
      Lander = Data.define(:x, :y, :carrying, :kind)
      Human = Data.define(:x, :y, :state)
      WORLD_WIDTH = 256
      WIDTH = 32
      HEIGHT = 20

      attr_reader :player_x, :player_y, :direction, :landers, :humans,
                  :shots, :score, :lives, :bombs

      def initialize
        @bitmap = Media::Bitmap.new(WIDTH, HEIGHT)
        @player_x = 24
        @player_y = 10
        @direction = 1
        @score = 0
        @lives = 3
        @bombs = 3
        @sound_events = [:start]
        @shots = []
        @humans = 8.times.map { |index| Human.new(x: 12 + index * 29, y: 17, state: :ground) }
        @landers = 6.times.map do |index|
          Lander.new(x: 35 + index * 37, y: 4 + index % 4, carrying: nil, kind: :lander)
        end
        render
      end

      def handle(event)
        return false unless event.fetch("kind", 0) == Input::KEY_DOWN

        case event.fetch("code", 0)
        when 97, LEFT_KEY
          @direction = -1
          @player_x = (player_x - 2) % WORLD_WIDTH
        when 100, RIGHT_KEY
          @direction = 1
          @player_x = (player_x + 2) % WORLD_WIDTH
        when 119, UP_KEY then @player_y = [player_y - 1, 3].max
        when 115, DOWN_KEY then @player_y = [player_y + 1, 16].min
        when 32 then fire
        when 98, 66 then smart_bomb
        else return false
        end
        render
        true
      end

      def fire
        if shots.length < 6
          @shots << [((player_x + direction * 2) % WORLD_WIDTH), player_y, direction, 18]
          emit_sound(:fire)
        end
        self
      end

      def smart_bomb
        return self unless bombs.positive?

        @bombs -= 1
        emit_sound(:bomb)
        visible, hidden = landers.partition { |enemy| screen_x(enemy.x).between?(0, WIDTH - 1) }
        visible.each do |enemy|
          next unless enemy.carrying

          human = humans.fetch(enemy.carrying)
          @humans[enemy.carrying] = Human.new(x: human.x, y: human.y, state: :falling)
        end
        @score += visible.length * 150
        @landers = hidden
        self
      end

      def tick
        update_landers
        update_shots
        update_humans
        if landers.any? { |enemy| screen_x(enemy.x).between?(14, 17) && (enemy.y - player_y).abs <= 1 }
          @lives -= 1
          emit_sound(@lives.positive? ? :danger : :game_over)
          @player_y = 10
        end
        render
        self
      end

      def view = @bitmap
      def status
        "SCORE #{score}  SHIPS #{lives}  BOMBS #{bombs}"
      end

      private

      def circular_delta(target, origin)
        delta = (target - origin) % WORLD_WIDTH
        delta > WORLD_WIDTH / 2 ? delta - WORLD_WIDTH : delta
      end

      def screen_x(world_x) = 16 + circular_delta(world_x, player_x)

      def update_landers
        next_humans = humans.dup
        @landers = landers.map do |enemy|
          if enemy.carrying
            human = next_humans.fetch(enemy.carrying)
            y = enemy.y - 1
            if y <= 2
              next_humans[enemy.carrying] = Human.new(x: human.x, y: 17, state: :lost)
              Lander.new(x: enemy.x, y: 3, carrying: nil, kind: :mutant)
            else
              next_humans[enemy.carrying] = Human.new(x: enemy.x, y: y + 1, state: :carried)
              Lander.new(x: enemy.x, y:, carrying: enemy.carrying, kind: enemy.kind)
            end
          else
            candidates = next_humans.each_index.select { |index| next_humans[index].state == :ground }
            target_index = candidates.min_by { |index| circular_delta(next_humans[index].x, enemy.x).abs }
            if target_index
              target = next_humans.fetch(target_index)
              x = (enemy.x + (circular_delta(target.x, enemy.x) <=> 0)) % WORLD_WIDTH
              y = enemy.y + (target.y - enemy.y <=> 0)
              if circular_delta(target.x, x).abs <= 1 && (target.y - y).abs <= 1
                next_humans[target_index] = Human.new(x:, y: y + 1, state: :carried)
                Lander.new(x:, y:, carrying: target_index, kind: enemy.kind)
              else
                Lander.new(x:, y:, carrying: nil, kind: enemy.kind)
              end
            else
              speed = enemy.kind == :mutant ? 2 : 1
              Lander.new(x: (enemy.x + (circular_delta(player_x, enemy.x) <=> 0) * speed) % WORLD_WIDTH,
                         y: enemy.y + (player_y - enemy.y <=> 0), carrying: nil, kind: enemy.kind)
            end
          end
        end
        @humans = next_humans
      end

      def update_shots
        survivors = landers.dup
        next_shots = []
        shots.each do |x, y, heading, ttl|
          x = (x + heading * 2) % WORLD_WIDTH
          ttl -= 1
          target = survivors.find { |enemy| circular_delta(enemy.x, x).abs <= 1 && (enemy.y - y).abs <= 1 }
          if target
            survivors.delete(target)
            emit_sound(:hit)
            @score += target.kind == :mutant ? 250 : 150
            if target.carrying
              human = humans.fetch(target.carrying)
              @humans[target.carrying] = Human.new(x: human.x, y: human.y, state: :falling)
            end
          elsif ttl.positive?
            next_shots << [x, y, heading, ttl]
          end
        end
        @landers = survivors
        @shots = next_shots
      end

      def update_humans
        @humans = humans.map do |human|
          case human.state
          when :falling
            if circular_delta(human.x, player_x).abs <= 2 && (human.y - player_y).abs <= 2
              @score += 250
              emit_sound(:rescue)
              Human.new(x: player_x, y: player_y + 1, state: :aboard)
            elsif human.y >= 17
              Human.new(x: human.x, y: 17, state: :ground)
            else
              Human.new(x: human.x, y: human.y + 1, state: :falling)
            end
          when :aboard
            if player_y >= 16
              @score += 500
              emit_sound(:rescue)
              Human.new(x: player_x, y: 17, state: :ground)
            else
              Human.new(x: player_x, y: player_y + 1, state: :aboard)
            end
          else
            human
          end
        end
      end

      def render
        @bitmap.clear(0x030817)
        20.times do |index|
          sx = (index * 11 - player_x / 2) % WIDTH
          @bitmap.put(sx, 3 + index * 7 % 12, 0x496785)
        end
        WIDTH.times { |x| @bitmap.put(x, 18, 0x426b3a) }
        humans.each do |human|
          x = screen_x(human.x)
          @bitmap.put(x, human.y, human.state == :lost ? 0x493542 : 0xffd866) if x.between?(0, WIDTH - 1)
        end
        landers.each do |enemy|
          x = screen_x(enemy.x)
          @bitmap.rect(x, enemy.y, 2, 1, color: enemy.kind == :mutant ? 0xff668a : 0x78dce8) if x.between?(-1, WIDTH - 1)
          radar_x = enemy.x * WIDTH / WORLD_WIDTH
          @bitmap.put(radar_x, 1, 0xff668a)
        end
        shots.each do |x, y, _heading, _ttl|
          sx = screen_x(x)
          @bitmap.put(sx, y, 0xffffff) if sx.between?(0, WIDTH - 1)
        end
        @bitmap.rect(15, player_y, 3, 1, color: 0x51d6c5)
        @bitmap.put(player_x * WIDTH / WORLD_WIDTH, 0, 0x51d6c5)
      end
    end
  end

  module Apps
    module ArcadeArt
      module_function

      INVADER = ["  XX  ", " XXXX ", "XXXXXX", "XX  XX", " X  X "].freeze
      RAIDER = ["  XX  ", " XXXXXX ", "XXXXXXXX", " XX  XX ", "X  XX  X"].freeze
      SHIP = ["    X   ", "   XXX  ", "XXXXXXX ", " XXXXXXX", "  X  X  "].freeze
      LANDER = ["  XXXX  ", " XXXXXX ", "XX XX XX", "  X  X  ", " X    X "].freeze
      GHOST = [" XXXX ", "XXXXXX", "XXOOXX", "XXXXXX", "X X X "].freeze

      def render(game, scale)
        source = game.view
        target = Media::Bitmap.new(source.width * scale, source.height * scale)
        background = source.get(0, 0) || 0x02040c
        target.height.times do |y|
          shade = adjust(background, 1.0 + 0.35 * y / [target.height, 1].max)
          target.rect(0, y, target.width, 1, color: shade)
        end
        60.times do |index|
          x = (index * 97 + 19) % target.width
          y = (index * 53 + 11) % target.height
          target.rect(x, y, index % 7 == 0 ? 2 : 1, 1,
                      color: index.even? ? 0x496785 : 0x26344d)
        end
        case game
        when Games::Invaders then invaders(target, game, scale)
        when Games::Snake then snake(target, game, scale)
        when Games::Maze then maze(target, game, scale)
        when Games::Raiders then raiders(target, game, scale)
        when Games::Defender then defender(target, game, scale)
        else
          source.each_pixel do |x, y, color|
            tile(target, x, y, scale, color) unless color == background
          end
        end
        target
      end

      def enhance(source, scale)
        wrapper = Struct.new(:view).new(source)
        render(wrapper, scale)
      end

      def invaders(target, game, cell)
        game.enemies.each do |x, y|
          stamp(target, INVADER, x * cell - cell / 2, y * cell - cell / 3,
                color: 0x89ddff, accent: 0xe8fbff, unit: [cell / 4, 1].max)
        end
        stamp(target, SHIP, game.player_x * cell - cell, 18 * cell - cell / 2,
              color: 0xffd866, accent: 0xffffff, unit: [cell / 4, 1].max)
        projectile(target, game.shot, cell, 0xff668a)
      end

      def snake(target, game, cell)
        game.body.reverse_each.with_index do |(x, y), index|
          color = index == game.body.length - 1 ? 0xe5ffb8 : 0x72d66d
          target.rect(x * cell + 1, y * cell + 1, cell - 2, cell - 2,
                      color: adjust(color, 0.65))
          target.rect(x * cell + 2, y * cell + 2, cell - 4, cell - 4, color:)
        end
        head_x, head_y = game.body.first
        target.rect(head_x * cell + cell - 3, head_y * cell + 2, 2, 2, color: 0x08140e)
        food_x, food_y = game.food
        disc(target, food_x * cell + cell / 2, food_y * cell + cell / 2,
             [cell / 2 - 1, 2].max, 0xff668a)
        target.line(food_x * cell + cell / 2, food_y * cell + 1,
                    food_x * cell + cell / 2 + 2, food_y * cell - 2, color: 0x8fe388)
      end

      def maze(target, game, cell)
        Games::Maze::HEIGHT.times do |y|
          Games::Maze::WIDTH.times do |x|
            next unless game.send(:wall?, x, y)
            tile(target, x, y, cell, 0x375bd2)
          end
        end
        game.pellets.each_key do |x, y|
          size = [cell / 4, 2].max
          target.rect(x * cell + (cell - size) / 2, y * cell + (cell - size) / 2,
                      size, size, color: 0xffd866)
        end
        game.ghosts.each do |ghost|
          stamp(target, GHOST, ghost.x * cell - cell / 3, ghost.y * cell - cell / 3,
                color: ghost.color, accent: 0xffffff, unit: [cell / 5, 1].max)
        end
        x, y = game.player
        disc(target, x * cell + cell / 2, y * cell + cell / 2, cell / 2, 0xffff80)
        target.rect(x * cell + cell / 2, y * cell + cell / 2 - 1,
                    cell / 2, 3, color: background_color(target, x * cell, y * cell))
      end

      def raiders(target, game, cell)
        game.enemies.each do |enemy|
          stamp(target, RAIDER, enemy.x * cell - cell / 2, enemy.y * cell - cell / 3,
                color: enemy.diving ? 0xff668a : 0x51d6c5, accent: 0xffffff,
                unit: [cell / 5, 1].max)
        end
        stamp(target, SHIP, (game.player_x - 1) * cell, 18 * cell - cell / 2,
              color: 0xffd866, accent: 0xffffff, unit: [cell / 4, 1].max)
        projectile(target, game.shot, cell, 0xffffff)
      end

      def defender(target, game, cell)
        terrain_y = 18 * cell
        target.rect(0, terrain_y, target.width, target.height - terrain_y, color: 0x183a2b)
        (0...target.width).step([cell / 2, 1].max) do |x|
          ridge = ((x / [cell / 2, 1].max * 7 + game.player_x) % 11) * cell / 12
          target.rect(x, terrain_y - ridge, [cell / 2, 1].max, ridge + 2,
                      color: 0x426b3a)
        end
        game.humans.each do |human|
          x = game.send(:screen_x, human.x)
          next unless x.between?(0, Games::Defender::WIDTH - 1)
          color = human.state == :lost ? 0x493542 : 0xffd866
          px, py = x * cell + cell / 2, human.y * cell
          disc(target, px, py, [cell / 5, 1].max, color)
          target.line(px, py + cell / 4, px, py + cell - 2, color:)
          target.line(px, py + cell / 2, px - cell / 3, py + cell * 3 / 4, color:)
          target.line(px, py + cell / 2, px + cell / 3, py + cell * 3 / 4, color:)
        end
        game.landers.each do |enemy|
          x = game.send(:screen_x, enemy.x)
          next unless x.between?(-2, Games::Defender::WIDTH + 1)
          stamp(target, LANDER, x * cell - cell / 2, enemy.y * cell - cell / 3,
                color: enemy.kind == :mutant ? 0xff668a : 0x78dce8,
                accent: 0xffffff, unit: [cell / 5, 1].max)
          radar_x = enemy.x * target.width / Games::Defender::WORLD_WIDTH
          target.rect(radar_x, cell, [cell / 3, 2].max, [cell / 4, 2].max, color: 0xff668a)
        end
        game.shots.each do |x, y, heading, _ttl|
          sx = game.send(:screen_x, x)
          next unless sx.between?(0, Games::Defender::WIDTH - 1)
          start = sx * cell + (heading.negative? ? -cell : 0)
          target.rect(start, y * cell + cell / 2, cell * 2, 2, color: 0xffffff)
        end
        stamp(target, SHIP, 15 * cell - cell / 2, game.player_y * cell - cell / 2,
              color: 0x51d6c5, accent: 0xffffff, unit: [cell / 4, 1].max)
        radar_x = game.player_x * target.width / Games::Defender::WORLD_WIDTH
        target.rect(radar_x, 0, [cell / 2, 2].max, [cell / 3, 2].max, color: 0x51d6c5)
      end

      def tile(target, x, y, cell, color)
        left, top = x * cell, y * cell
        target.rect(left, top, cell, cell, color: adjust(color, 0.55))
        target.rect(left + 1, top + 1, [cell - 2, 1].max, [cell - 2, 1].max, color:)
        target.line(left + 1, top + 1, left + cell - 2, top + 1,
                    color: adjust(color, 1.35)) if cell >= 4
      end

      def stamp(target, pattern, x, y, color:, accent:, unit: 1)
        pattern.each_with_index do |row, row_index|
          row.each_char.with_index do |pixel, column|
            next if pixel == " "
            shade = pixel == "O" ? 0x07101e : (row_index.zero? ? accent : color)
            target.rect(x + column * unit, y + row_index * unit, unit, unit, color: shade)
          end
        end
      end

      def projectile(target, point, cell, color)
        return unless point
        x, y = point
        target.rect(x * cell + cell / 2 - 1, y * cell, 3, cell, color:)
      end

      def disc(target, center_x, center_y, radius, color)
        (-radius..radius).each do |offset|
          half = Math.sqrt([radius * radius - offset * offset, 0].max).to_i
          target.rect(center_x - half, center_y + offset, half * 2 + 1, 1, color:)
        end
      end

      def background_color(target, x, y) = target.get(x, y) || 0x03040d

      def adjust(color, factor)
        channels = [16, 8, 0].map { |shift| [[((color >> shift) & 0xff) * factor, 255].min, 0].max.to_i }
        (channels[0] << 16) | (channels[1] << 8) | channels[2]
      end
    end

    class ArcadeView < GUI::View
      def initialize(game, scale: 4, on_change: nil, on_sound: nil, **options)
        super(**options)
        @game = game
        @scale = scale
        @on_change = on_change
        @on_sound = on_sound
      end

      def handle(event)
        handled = @game.handle(event)
        if handled
          @on_change&.call
          @on_sound&.call
          invalidate
        end
        handled
      end

      def draw(surface)
        if @art_revision != @game.view.revision
          @render_scale = @scale.even? ? @scale / 2 : @scale
          @present_scale = @scale / @render_scale
          @art = ArcadeArt.render(@game, @render_scale)
          @art_revision = @game.view.revision
        end
        surface.draw_bitmap(x, y, @art, scale: @present_scale)
      end

      def focusable? = true

      def release
        @art = nil
        @art_revision = nil
        self
      end
    end

    class ArcadeApplication < Application
      attr_reader :game

      def advance(*)
        game.tick
        play_pending_cues
        update_status
        @arcade&.invalidate
        true
      end

      def toggle_pause(*)
        @paused = !@paused
        update_status
        true
      end

      def menus(compositor)
        [GUI::Menu.new(title: "Game", items: [
          GUI::MenuItem.command("Pause / Resume", shortcut: "Space") { toggle_pause }
        ]), *super]
      end

      private

      def build_arcade_window(title, instructions:, x:, y:, scale: nil, background: 0x080b18,
                              tick_every: 4)
        bitmap = game.view
        scale ||= @compositor&.width.to_i >= 900 ? 20 : 8
        width = bitmap.width * scale + 36
        height = bitmap.height * scale + 72
        @tick_count = 0
        @paused = false
        @window = GUI::Window.new(title, x:, y:, width:, height:, resizable: false,
                                  background:)
        @arcade = @window.add(ArcadeView.new(
          game, scale:, x: 0, y: 0, width: bitmap.width * scale,
          height: bitmap.height * scale, on_change: method(:update_status),
          on_sound: method(:play_pending_cues)
        ))
        @status = @window.add(GUI::Label.new("", x: 0, y: bitmap.height * scale + 4,
                                             width: bitmap.width * scale, color: 0xffd866))
        @instructions = @window.add(GUI::Label.new(
          instructions, x: 0, y: bitmap.height * scale + 24,
          width: bitmap.width * scale, color: 0xa8d8ff
        ))
        @window.focus_child(@arcade)
        @window.on_tick do
          @tick_count += 1
          advance if !@paused && (@tick_count % tick_every).zero?
        end
        @window.on_close do
          @arcade&.release
          @arcade = @status = @instructions = @window = nil
          GC.start
        end
        update_status
        play_pending_cues
        @window
      end

      def play_pending_cues
        output = @compositor&.audio_output
        return false unless output && game.respond_to?(:cue)

        played = false
        while (pcm = game.cue)
          output.play(pcm)
          played = true
        end
        played
      rescue RubyOS::Error
        false
      end

      def update_status
        @status.text = "#{game.status}#{@paused ? '  |  PAUSED' : ''}" if @status
        @status&.invalidate
        true
      end
    end

    class Invaders < ArcadeApplication
      def initialize(**options)
        super
        @game = Games::Invaders.new
      end

      def build_window
        build_arcade_window("Ruby Invaders", instructions: "A/D or arrows move  |  Space fire",
                            x: 72, y: 26, background: 0x080b18)
      end
    end

    class Snake < ArcadeApplication
      def initialize(**options)
        super
        @game = Games::Snake.new
      end

      def build_window
        build_arcade_window("Ruby Snake", instructions: "W/A/S/D steer",
                            x: 136, y: 26, background: 0x08140e)
      end
    end

    class Maze < ArcadeApplication
      def initialize(**options)
        super
        @game = Games::Maze.new
      end

      def build_window
        build_arcade_window("Enumerable Maze", instructions: "W/A/S/D or arrows chase gems",
                            x: 104, y: 32, background: 0x060716, tick_every: 5)
      end
    end

    class Raiders < ArcadeApplication
      def initialize(**options)
        super
        @game = Games::Raiders.new
      end

      def build_window
        build_arcade_window("Data Raiders", instructions: "A/D or arrows move  |  Space fire",
                            x: 92, y: 26, background: 0x050817, tick_every: 4)
      end
    end

    class Defender < ArcadeApplication
      def initialize(**options)
        super
        @game = Games::Defender.new
      end

      def build_window
        build_arcade_window("Ruby Defender", instructions: "WASD FLY | SPACE FIRE | B BOMB",
                            x: 76, y: 26, background: 0x030817, tick_every: 3)
      end
    end
  end
end
