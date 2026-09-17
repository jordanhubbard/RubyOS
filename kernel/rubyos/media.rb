# frozen_string_literal: true

module RubyOS
  module Media
    class Color
      def self.hex(value)
        text = String(value).delete_prefix("#")
        raise ArgumentError, "expected six hex digits" unless /\A[0-9a-fA-F]{6}\z/.match?(text)
        text.to_i(16)
      end
      def self.rgb(red, green, blue)
        channels = [red, green, blue].map { |n| Integer(n) }
        raise ArgumentError, "RGB channels must be 0..255" unless channels.all? { |n| (0..255).cover?(n) }
        channels[0] << 16 | channels[1] << 8 | channels[2]
      end
    end

    # A plain image, not an emulated display chipset. Useful for game artwork.
    class Bitmap
      attr_reader :width, :height, :revision
      def initialize(width, height, background: 0)
        @width, @height = Integer(width), Integer(height)
        raise ArgumentError, "invalid bitmap dimensions" unless [@width, @height].all? { |n| (1..2048).cover?(n) }
        @pixels = Array.new(@width * @height, Integer(background))
        @revision = 0
      end
      def put(x, y, color)
        if x.between?(0, width - 1) && y.between?(0, height - 1)
          index = y * width + x
          value = Integer(color)
          if @pixels[index] != value
            @pixels[index] = value
            @revision += 1
          end
        end
        self
      end
      def get(x, y)
        return nil unless x.between?(0, width - 1) && y.between?(0, height - 1)

        @pixels[y * width + x]
      end
      def clear(color = 0)
        value = Integer(color)
        return self if @pixels.all? { |pixel| pixel == value }

        @pixels.fill(value)
        @revision += 1
        self
      end
      def rect(x, y, width, height, color:)
        height.times { |row| width.times { |column| put(x + column, y + row, color) } }
        self
      end
      def line(x0, y0, x1, y1, color:)
        x0, y0, x1, y1 = [x0, y0, x1, y1].map { |value| Integer(value) }
        clipped = clip_line(x0, y0, x1, y1)
        return self unless clipped

        x0, y0, x1, y1 = clipped
        dx = (x1 - x0).abs
        sx = x0 < x1 ? 1 : -1
        dy = -(y1 - y0).abs
        sy = y0 < y1 ? 1 : -1
        error = dx + dy
        loop do
          put(x0, y0, color)
          break if x0 == x1 && y0 == y1

          doubled = error * 2
          if doubled >= dy
            error += dy
            x0 += sx
          end
          if doubled <= dx
            error += dx
            y0 += sy
          end
        end
        self
      end
      def each_pixel
        return enum_for(:each_pixel) unless block_given?

        height.times do |y|
          width.times { |x| yield x, y, @pixels[y * width + x] }
        end
        self
      end
      def raster = @pixels.dup
      def bytes = @pixels.pack("L<*")

      private

      def clip_line(x0, y0, x1, y1)
        8.times do
          code0 = outcode(x0, y0)
          code1 = outcode(x1, y1)
          return [x0, y0, x1, y1] if (code0 | code1).zero?
          return nil unless (code0 & code1).zero?

          code = code0.zero? ? code1 : code0
          if (code & 8).positive?
            x = x0 + (x1 - x0) * (height - 1 - y0) / (y1 - y0)
            y = height - 1
          elsif (code & 4).positive?
            x = x0 + (x1 - x0) * -y0 / (y1 - y0)
            y = 0
          elsif (code & 2).positive?
            y = y0 + (y1 - y0) * (width - 1 - x0) / (x1 - x0)
            x = width - 1
          else
            y = y0 + (y1 - y0) * -x0 / (x1 - x0)
            x = 0
          end
          if code == code0
            x0, y0 = x, y
          else
            x1, y1 = x, y
          end
        end
        nil
      end

      def outcode(x, y)
        code = 0
        code |= 1 if x.negative?
        code |= 2 if x >= width
        code |= 4 if y.negative?
        code |= 8 if y >= height
        code
      end
    end

    class Timeline
      Track = Data.define(:target, :property, :from, :to, :start, :duration, :easing)
      attr_reader :time
      def initialize
        @time = 0.0
        @tracks = []
      end
      def animate(target, property, to:, duration:, from: nil, delay: 0, easing: :smooth)
        duration, delay = Float(duration), Float(delay)
        raise ArgumentError, "invalid animation timing" unless duration.finite? && duration.positive? && delay.finite? && delay >= 0
        raise ArgumentError, "unknown easing" unless %i[linear smooth].include?(easing)
        from = Float(from.nil? ? target.public_send(property) : from)
        to = Float(to)
        raise ArgumentError, "nonfinite animation value" unless from.finite? && to.finite?
        @tracks << Track.new(target, property, from, to, time + delay, duration, easing)
        self
      end
      def seek(seconds)
        seconds = Float(seconds)
        raise ArgumentError, "invalid time" unless seconds.finite? && seconds >= 0
        @time = seconds
        # Restore the earliest baseline, then apply only tracks which have begun.
        @tracks.reverse_each { |track| track.target.public_send("#{track.property}=", track.from) }
        @tracks.each do |track|
          next if time < track.start
          progress = [[(time - track.start) / track.duration, 0].max, 1].min
          progress = progress * progress * (3 - 2 * progress) if track.easing == :smooth
          track.target.public_send("#{track.property}=", track.from + (track.to - track.from) * progress)
        end
        self
      end
      def advance(seconds) = seek(time + Float(seconds))
      def clear
        @tracks.clear
        self
      end
    end

    class Shape
      attr_accessor :x, :y, :width, :height, :color, :text
      def initialize(x:, y:, width: 0, height: 0, color: 0xffffff, text: nil)
        @x, @y, @width, @height, @color, @text = x, y, width, height, color, text
      end
      def draw(canvas)
        if text
          canvas.text(text, x: x.round, y: y.round, color:)
        else
          canvas.rect(x.round, y.round, width.round, height.round, color:)
        end
      end
    end
    class Scene
      attr_accessor :background
      attr_reader :nodes
      def initialize(background: 0x111827)
        @background, @nodes = background, []
      end
      def rect(**options) = add(Shape.new(**options))
      def text(value, **options) = add(Shape.new(text: String(value), **options))
      def add(node)
        @nodes << node
        node
      end
      def draw(canvas)
        canvas.clear(background)
        nodes.each { |node| node.draw(canvas) }
        canvas
      end
    end

    class Camera
      attr_accessor :x, :y, :z, :fov, :near, :far
      def initialize(x: 0, y: 0, z: 5, fov: 55, near: 0.1, far: 100)
        @x, @y, @z, @fov, @near, @far = x, y, z, fov, near, far
      end
      def project(point, aspect:)
        raise ArgumentError, "invalid camera frustum" unless near > 0 && far > near && fov > 0 && fov < 180 && aspect > 0
        px, py, pz = point[0] - x, point[1] - y, point[2] - z
        f = 1.0 / Math.tan(fov * Math::PI / 360)
        [px * f / aspect, py * f, (far + near) / (near - far) * pz + 2.0 * far * near / (near - far), -pz]
      end
    end

    class Mesh
      attr_reader :points, :faces
      attr_accessor :x, :y, :z, :rotation_x, :rotation_y, :rotation_z, :scale
      def initialize(points:, faces:)
        @points, @faces = points.map { |v| v.map { |n| Float(n) }.freeze }.freeze, faces.map(&:freeze).freeze
        raise ArgumentError, "invalid mesh points" unless @points.all? { |v| v.length == 3 && v.all?(&:finite?) }
        raise ArgumentError, "invalid mesh faces" unless @faces.all? { |f| f.length == 4 && f.first(3).all? { |i| i.is_a?(Integer) && i >= 0 && i < @points.length } && f[3].is_a?(Integer) }
        @x = @y = @z = @rotation_x = @rotation_y = @rotation_z = 0.0
        @scale = 1.0
      end
      def self.cube(size: 2)
        s = Float(size) / 2
        points = [[-s,-s,-s],[s,-s,-s],[s,s,-s],[-s,s,-s],[-s,-s,s],[s,-s,s],[s,s,s],[-s,s,s]]
        faces = [[0,1,2,0x8266ff],[0,2,3,0x8266ff],[4,6,5,0x51d6c5],[4,7,6,0x51d6c5],
                 [0,4,5,0xff718d],[0,5,1,0xff718d],[3,2,6,0xffce73],[3,6,7,0xffce73],
                 [1,5,6,0x68aaff],[1,6,2,0x68aaff],[0,3,7,0xb396ff],[0,7,4,0xb396ff]]
        new(points:, faces:)
      end
      def vertices(camera, aspect:)
        sx, cx = Math.sin(rotation_x), Math.cos(rotation_x)
        sy, cy = Math.sin(rotation_y), Math.cos(rotation_y)
        sz, cz = Math.sin(rotation_z), Math.cos(rotation_z)
        transformed = points.map do |px, py, pz|
          px, py, pz = px * scale, py * scale, pz * scale
          py, pz = py * cx - pz * sx, py * sx + pz * cx
          px, pz = px * cy + pz * sy, -px * sy + pz * cy
          px, py = px * cz - py * sz, px * sz + py * cz
          camera.project([px + x, py + y, pz + z], aspect:)
        end
        faces.flat_map do |a, b, c, color|
          rgb = [(color >> 16 & 255) / 255.0, (color >> 8 & 255) / 255.0, (color & 255) / 255.0]
          [transformed[a] + rgb, transformed[b] + rgb, transformed[c] + rgb]
        end
      end
    end
    class Scene3D
      attr_accessor :background
      attr_reader :camera, :meshes
      def initialize(camera: Camera.new, background: 0x111827)
        @camera, @background, @meshes = camera, background, []
      end
      def add(mesh)
        meshes << mesh
        mesh
      end
      def vertices(aspect:) = meshes.flat_map { |mesh| mesh.vertices(camera, aspect:) }
    end

    class AudioTrack
      def initialize(output)
        @output = output
        @voices = []
      end
      def tone(frequency, duration: 0.25, amplitude: 0.2)
        frequency, duration, amplitude = Float(frequency), Float(duration), Float(amplitude)
        raise ArgumentError, "invalid tone" unless frequency.finite? && frequency > 0 && frequency <= @output.rate / 2.0 && duration.finite? && duration > 0 && duration <= 10 && amplitude.finite? && (0..1).cover?(amplitude)
        raise ArgumentError, "at most 32 voices" if @voices.length >= 32
        @voices << Sound::Waveform.sine(frequency, duration_ms: Float(duration) * 1000, amplitude:, rate: @output.rate)
        self
      end
      def play
        @output.play(Sound::Mixer.new.mix(*@voices))
        @voices.clear
        self
      end
    end

    class Studio
      attr_reader :session, :display, :timeline
      def self.open(client, **options)
        SDL.open(client) do |session|
          studio = new(session, **options)
          yield studio
        end
      end
      def initialize(session, **options)
        @session = session
        @display = session.display(**options)
        @timeline = Timeline.new
      end
      def canvas = display.canvas
      # Offline, fixed-step export. Audio callback returns one frame's stereo
      # S16LE bytes, or a PCM object with exactly 48000/fps mono samples.
      def record(seconds:, fps: 30, audio: nil)
        seconds, fps = Float(seconds), Integer(fps)
        raise ArgumentError, "recording requires 0 < seconds <= 60" unless seconds.finite? && seconds > 0 && seconds <= 60
        raise ArgumentError, "fps must divide 48000 and be 1..60" unless (1..60).cover?(fps) && 48000 % fps == 0
        count = (seconds * fps).ceil
        session.encoder(width: canvas.width, height: canvas.height, fps:, audio: !audio.nil?) do |encoder|
          count.times do |index|
            time = index.fdiv(fps)
            timeline.seek(time)
            yield canvas, time
            pcm = audio ? audio.call(time, 48000 / fps) : +"".b
            if pcm.is_a?(Sound::PCM)
              raise ArgumentError, "recording PCM must be 48000 Hz" unless pcm.rate == 48000
              pcm = pcm.stereo_bytes
            end
            encoder.frame(canvas, pcm:)
          end
          encoder.finish
        end
      end
      def frame(seconds: nil)
        timeline.seek(seconds) unless seconds.nil?
        yield canvas
        display.present
      end
      def run(fps: 60, frames: nil)
        fps = Float(fps)
        raise ArgumentError, "fps must be 1..240" unless (1..240).cover?(fps)
        started = now
        index = 0
        loop do
          break if frames && index >= frames
          events = frame(seconds: now - started) { |canvas| yield self, canvas }
          break if events.any? { |event| event.kind == 6 || event.kind == Input::QUIT }
          index += 1
          remaining = started + index / fps - now
          if remaining > 0
            if defined?(HAL) && HAL.respond_to?(:sleep_us)
              HAL.sleep_us((remaining * 1_000_000).to_i)
            else
              sleep remaining
            end
          end
        end
      end
      def now
        if defined?(HAL) && HAL.respond_to?(:monotonic_ns)
          HAL.monotonic_ns / 1_000_000_000.0
        else
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
