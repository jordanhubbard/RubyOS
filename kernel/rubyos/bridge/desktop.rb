# frozen_string_literal: true

module RubyOS
  module Bridge
    class Font
      attr_reader :client, :handle, :point_size

      def self.open_default(client, point_size: 16)
        path = client.sdl_call("host.default_font_path").fetch("path")
        open(client, path, point_size:)
      end

      def self.open(client, path, point_size: 16)
        result = client.sdl_call("TTF_Init")
        raise Error.new(11, "SDL_ttf initialization failed") unless result.fetch("rc", -1).zero?
        opened = client.sdl_call("TTF_OpenFont", String(path), Integer(point_size))
        new(client, opened.fetch("handle"), Integer(point_size))
      end

      def initialize(client, handle, point_size)
        @client = client
        @handle = Integer(handle)
        @point_size = point_size
        @closed = false
      end

      def measure(text)
        result = client.sdl_call("TTF_SizeUTF8", handle, String(text))
        raise Error.new(11, "font measurement failed") unless result.fetch("rc", -1).zero?
        [result.fetch("w"), result.fetch("h")]
      end

      def render(text, color: 0xffffff)
        rgba = (Integer(color) << 8) | 0xff
        result = client.sdl_call("TTF_RenderUTF8_Blended", handle, String(text), rgba)
        Surface.new(client, handle: result.fetch("handle"), width: result.fetch("w"),
                    height: result.fetch("h"), owned: true)
      end

      def close
        return self if @closed
        client.sdl_call("TTF_CloseFont", handle)
        @closed = true
        self
      end
    end

    class Surface
      attr_reader :client, :handle, :width, :height

      def initialize(client, handle:, width:, height:, owned: false)
        @client = client
        @handle = Integer(handle)
        @width = Integer(width)
        @height = Integer(height)
        @owned = owned
      end


      def self.create(client, width:, height:)
        result = client.call("surface.create", { w: width, h: height })
        new(client, handle: result.fetch("handle"), width:, height:, owned: true)
      end

      def self.load_image(client, bytes)
        result = client.call("surface.load_image", {}, payload: String(bytes).b)
        new(client, handle: result.fetch("handle"), width: result.fetch("w"),
            height: result.fetch("h"), owned: true)
      end

      def fill_rect(x, y, width, height, color)
        client.cast("surface.fill_rect", { handle:, rgb: Integer(color),
                    rect: { x:, y:, w: width, h: height } })
        self
      end

      def line(x0, y0, x1, y1, color)
        client.cast("surface.line", { handle:, x0:, y0:, x1:, y1:, rgb: Integer(color) })
        self
      end

      def draw_text(x, y, text, color: 0xffffff, background: nil)
        parameters = { handle:, x:, y:, text: String(text), fg: Integer(color) }
        parameters[:bg] = Integer(background) unless background.nil?
        client.cast("text.draw", parameters)
        self
      end


      def upload(pixels)
        pixels = String(pixels).b
        raise ArgumentError, "pixel buffer must contain width*height*4 bytes" unless pixels.bytesize == width * height * 4
        client.call("surface.upload", { handle: }, payload: pixels)
        self
      end

      def draw_bitmap(x, y, bitmap, scale: 1)
        scale = Integer(scale)
        raise ArgumentError, "bitmap scale must be positive" unless scale.positive?

        @bitmap_cache ||= {}
        key = [bitmap.object_id, scale]
        cached = @bitmap_cache[key]
        unless cached
          cached = {
            surface: Surface.create(client, width: bitmap.width * scale,
                                    height: bitmap.height * scale),
            revision: nil
          }
          @bitmap_cache[key] = cached
        end
        if cached[:revision] != bitmap.revision
          target = cached.fetch(:surface)
          if scale == 1
            target.upload(bitmap.bytes)
          else
            client.call("surface.upload_scaled", {
              handle: target.handle, src_w: bitmap.width, src_h: bitmap.height,
              scale:, encoding: "raw"
            }, payload: bitmap.bytes)
          end
          cached[:revision] = bitmap.revision
        end
        cached.fetch(:surface).blit_to(self, x:, y:)
        self
      end

      def blit_to(destination, x:, y:, source_rect: nil)
        parameters = { src: handle, dst: destination.handle,
                       dst_rect: { x:, y:, w: width, h: height } }
        parameters[:src_rect] = source_rect if source_rect
        client.cast("surface.blit", parameters)
        destination
      end

      def destroy
        return self unless @owned
        client.cast("surface.destroy", { handle: })
        @owned = false
        self
      end
    end

    class RemoteDesktop
      attr_reader :client, :surface, :width, :height

      def initialize(client, width: 640, height: 400, title: "RubyOS")
        @client = client
        @width = Integer(width)
        @height = Integer(height)
        opened = client.call("display.open", { w: @width, h: @height, title: })
        @surface = Surface.new(client, handle: opened.fetch("fb_handle"),
                               width: @width, height: @height)
        @pending_events = []
      end

      def present
        result = client.call("frame.commit")
        @pending_events.concat(result.fetch("events", []))
        self
      end

      def events
        raw = if @pending_events.empty?
                client.call("event.poll").fetch("events", [])
              else
                @pending_events.shift(@pending_events.length)
              end
        raw.map { |event| Input::Event.from_bridge(event) }
      end

      def capture(path)
        client.call("debug.capture", { path: File.expand_path(path) })
        self
      end

      def close
        client.call("display.close")
        self
      end
    end
  end
end
