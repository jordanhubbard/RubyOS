# frozen_string_literal: true

module RubyOS
  # The service is language-neutral; ownership, blocks and useful names live here.
  module SDL
    class ClosedResource < RubyOS::Error; end
    class Unsupported < RubyOS::Error; end

    def self.open(client)
      session = Session.new(client)
      return session unless block_given?
      begin
        yield session
      ensure
        session.close
      end
    end

    class Session
      attr_reader :client, :capabilities, :limits
      def initialize(client)
        @client = client
        hello = client.hello
        @capabilities = client.features
        @limits = hello.fetch("limits", {}).freeze
        @resources = []
        @closed = false
      end
      def check!
        raise ClosedResource, "SDL session is closed" if @closed
      end
      def supports?(feature) = capabilities.include?(String(feature))
      def require!(feature)
        check!
        raise Unsupported, "service does not support #{feature}" unless supports?(feature)
      end
      def call(operation, params = {}, payload: +"".b)
        check!
        client.call(operation, params, payload:)
      end
      def draw(operation, params)
        check!
        client.cast(operation, params)
      end
      def own(resource)
        @resources << resource
        resource
      end
      def forget(resource) = @resources.delete(resource)
      def scope(resource)
        return resource unless block_given?
        begin
          yield resource
        ensure
          resource.close
        end
      end
      def canvas(width:, height:, &block)
        scope(own(Canvas.create(self, width:, height:)), &block)
      end
      def image(bytes, &block)
        require!("image.decode")
        result = call("surface.load_image", {}, payload: String(bytes).b)
        scope(own(Canvas.new(self, result.fetch("handle"), result.fetch("w"), result.fetch("h"))), &block)
      end
      def display(width: 960, height: 600, title: "RubyOS Studio", &block)
        raise RubyOS::Error, "one display per session" if @display && !@display.closed?
        @display = own(Display.new(self, width:, height:, title:))
        scope(@display, &block)
      end
      def font(path: nil, size: 18, &block)
        scope(own(Font.new(self, path:, size:)), &block)
      end
      def audio(rate: 48_000, &block)
        require!("audio.pcm")
        raise RubyOS::Error, "one audio device per session" if @audio && !@audio.closed?
        @audio = own(Audio.new(self, rate:))
        scope(@audio, &block)
      end
      def video(bytes, &block)
        require!("video.decode")
        scope(own(Video.new(self, bytes)), &block)
      end
      def encoder(width:, height:, fps: 30, audio: false, &block)
        require!("video.encode")
        scope(own(Encoder.new(self, width:, height:, fps:, audio:)), &block)
      end
      def events = call("event.poll").fetch("events", []).map { |event| Input::Event.from_bridge(event) }
      def inject(**event) = call("debug.event.inject", event)
      def ping = call("ping")
      def ticks = sdl("SDL_GetTicks").fetch("rc")
      def sdl(name, *args) = call("sdl.call", { name: String(name), args: })
      def performance(reset: false)
        check!
        client.performance_snapshot(reset:)
      end
      def capture(path) = call("debug.capture", { path: String(path) })
      def import(token, limit: 16 * 1024 * 1024)
        require!("file.drop")
        bytes = +"".b
        loop do
          part = call("host.file.read", { token: Integer(token), offset: bytes.bytesize, length: 32_768 })
          chunk = [part.fetch("data")].pack("H*")
          raise RubyOS::Error, "import exceeds limit" if bytes.bytesize + chunk.bytesize > limit
          bytes << chunk
          break if part.fetch("eof")
          raise RubyOS::Error, "import made no progress" if chunk.empty?
        end
        bytes
      end
      def export(name, bytes)
        require!("file.export")
        bytes = String(bytes).b
        token = call("host.export.begin", { name: String(name) }).fetch("token")
        begin
          offset = 0
          while offset < bytes.bytesize
            chunk = bytes.byteslice(offset, 32_768)
            result = call("host.export.chunk", { token: }, payload: chunk)
            raise RubyOS::Error, "short export write" unless result.fetch("bytes") == chunk.bytesize
            offset += chunk.bytesize
          end
          result = call("host.export.finish", { token: })
          token = nil
          result.fetch("path")
        ensure
          call("host.export.abort", { token: }) if token
        end
      end
      def close
        return if @closed
        error = nil
        @resources.reverse.each do |resource|
          begin
            resource.close
          rescue StandardError => failure
            error ||= failure
          end
        end
        begin
          client.close
        rescue StandardError => failure
          error ||= failure
        ensure
          @closed = true
        end
        raise error if error
      end
    end

    class Resource
      attr_reader :session, :handle
      def initialize(session, handle = nil)
        @session, @handle, @closed = session, handle, false
      end
      def closed? = @closed
      def mark_closed
        @closed = true
        session.forget(self)
      end
      def check!
        session.check!
        raise ClosedResource, "#{self.class} is closed" if closed?
      end
      def compatible!(other)
        check!; other.check!
        raise ArgumentError, "resources belong to different sessions" unless session.equal?(other.session)
      end
    end

    class Canvas < Resource
      attr_reader :width, :height
      def self.create(session, width:, height:)
        width, height = Integer(width), Integer(height)
        raise ArgumentError, "canvas dimensions must be 1..2048" unless [width, height].all? { |n| (1..2048).cover?(n) }
        new(session, session.call("surface.create", { w: width, h: height }).fetch("handle"), width, height)
      end
      def initialize(session, handle, width, height, owned: true)
        super(session, handle)
        @width, @height, @owned = width, height, owned
      end
      def clear(color = 0) = rect(0, 0, width, height, color:)
      def rect(x, y, w, h, color:)
        check!
        session.draw("surface.fill_rect", { handle:, rgb: Integer(color), rect: { x:, y:, w:, h: } })
        self
      end
      def line(x0, y0, x1, y1, color:)
        check!
        session.draw("surface.line", { handle:, x0:, y0:, x1:, y1:, rgb: Integer(color) })
        self
      end
      def text(text, x:, y:, color: 0xffffff, background: nil)
        check!
        params = { handle:, x:, y:, text: String(text), fg: Integer(color) }
        params[:bg] = Integer(background) unless background.nil?
        session.draw("text.draw", params)
        self
      end
      def scroll(dy)
        check!
        session.draw("surface.scroll", { handle:, dy: Integer(dy) })
        self
      end
      def blit(source, x: 0, y: 0, crop: nil)
        compatible!(source)
        params = { src: source.handle, dst: handle, dst_rect: { x:, y:, w: source.width, h: source.height } }
        params[:src_rect] = crop if crop
        session.draw("surface.blit", params)
        self
      end
      def upload(bytes)
        check!
        bytes = String(bytes).b
        raise ArgumentError, "expected width*height*4 BGRA bytes" unless bytes.bytesize == width * height * 4
        session.call("surface.upload", { handle: }, payload: bytes)
        self
      end
      def upload_scaled(bytes, width:, height:, scale: 1, encoding: "raw", present: false)
        check!
        session.call("surface.upload_scaled", { handle:, src_w: width, src_h: height, scale:, encoding:, present: }, payload: String(bytes).b)
        self
      end
      def render(scene)
        check!; session.require!("scene3d.render")
        session.call("scene3d.render", { handle:, clear: scene.background, vertices: scene.vertices(aspect: width.fdiv(height)) })
      end
      def close
        return if closed?
        session.call("surface.destroy", { handle: }) if @owned
        mark_closed
      end
    end

    class Display < Resource
      attr_reader :canvas
      def initialize(session, width:, height:, title:)
        super(session)
        raise ArgumentError, "display dimensions must be 1..2048" unless [width, height].all? { |n| n.is_a?(Integer) && (1..2048).cover?(n) }
        result = session.call("display.open", { w: width, h: height, title: String(title) })
        @canvas = Canvas.new(session, result.fetch("fb_handle"), width, height, owned: false)
      end
      def present
        check!
        session.call("frame.commit").fetch("events", []).map { |event| Input::Event.from_bridge(event) }
      end
      def present_async
        check!
        # Explicitly flush queued drawing before the ordered presentation.
        session.client.flush
        session.client.notify("display.present")
        self
      end
      def close
        return if closed?
        session.call("display.close")
        canvas.close
        mark_closed
      end
    end

    class Font < Resource
      def initialize(session, path:, size:)
        super(session)
        @font = path ? Bridge::Font.open(session.client, path, point_size: size) : Bridge::Font.open_default(session.client, point_size: size)
      end
      def measure(text)
        check!; @font.measure(String(text))
      end
      def render(text, color: 0xffffff)
        check!
        surface = @font.render(String(text), color: Integer(color))
        session.own(Canvas.new(session, surface.handle, surface.width, surface.height))
      end
      def close
        return if closed?
        @font.close; mark_closed
      end
    end

    class Audio < Resource
      attr_reader :rate
      def initialize(session, rate:)
        super(session)
        @rate = session.call("audio.open", { rate: Integer(rate) }).fetch("rate")
      end
      def play(pcm)
        check!
        raise ArgumentError, "sample rate mismatch" unless pcm.rate == rate
        session.call("audio.queue", {}, payload: pcm.stereo_bytes)
        self
      end
      def queued_bytes
        check!; session.call("audio.status").fetch("queued_bytes")
      end
      def close
        return if closed?
        session.call("audio.close"); mark_closed
      end
    end

    class Video < Resource
      attr_reader :width, :height
      def initialize(session, bytes)
        result = session.call("video.open", {}, payload: String(bytes).b)
        super(session, result.fetch("handle"))
        @width, @height = result.fetch("width"), result.fetch("height")
      end
      def frame(canvas)
        compatible!(canvas)
        result = session.call("video.frame", { handle:, destination: canvas.handle })
        result.fetch("eof") ? nil : result.fetch("seconds")
      end
      def seek(seconds)
        check!
        session.call("video.seek", { handle:, seconds: Float(seconds) })
        self
      end
      def play
        check!; session.require!("video.playback")
        session.call("video.play", { handle: })
        self
      end
      def pause
        check!; session.call("video.pause", { handle: })
        self
      end
      def tick(canvas)
        compatible!(canvas)
        session.call("video.tick", { handle:, destination: canvas.handle })
      end
      def close
        return if closed?
        session.call("video.close", { handle: }); mark_closed
      end
    end

    class Encoder < Resource
      attr_reader :fps
      def initialize(session, width:, height:, fps:, audio:)
        @fps, @audio = Integer(fps), audio
        @finished = false
        result = session.call("encoder.open", { width: Integer(width), height: Integer(height), fps: @fps, audio: !!audio })
        super(session, result.fetch("handle"))
      end
      # PCM bytes are stereo signed 16-bit little-endian, 48000/fps frames.
      def frame(canvas, pcm: +"".b)
        compatible!(canvas)
        raise RubyOS::Error, "encoder is finished" if @finished
        session.call("encoder.frame", { handle:, source: canvas.handle }, payload: String(pcm).b)
        self
      end
      def finish
        check!
        size = session.call("encoder.finish", { handle: }).fetch("bytes")
        @finished = true
        bytes = +"".b
        loop do
          part = session.call("encoder.read", { handle:, offset: bytes.bytesize })
          chunk = [part.fetch("data")].pack("H*")
          raise RubyOS::Error, "invalid encoded output" if bytes.bytesize + chunk.bytesize > size || (chunk.empty? && !part.fetch("eof"))
          bytes << chunk
          break if part.fetch("eof")
        end
        raise RubyOS::Error, "truncated encoded output" unless bytes.bytesize == size
        bytes
      end
      def close
        return if closed?
        session.call("encoder.close", { handle: }); mark_closed
      end
    end
  end
end
