# frozen_string_literal: true

module RubyOS
  module Bridge
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
        client.call("surface.fill_rect", { handle:, rgb: Integer(color),
                    rect: { x:, y:, w: width, h: height } })
        self
      end

      def draw_text(x, y, text, color: 0xffffff, background: nil)
        parameters = { handle:, x:, y:, text: String(text), fg: Integer(color) }
        parameters[:bg] = Integer(background) unless background.nil?
        client.call("text.draw", parameters)
        self
      end


      def upload(pixels)
        pixels = String(pixels).b
        raise ArgumentError, "pixel buffer must contain width*height*4 bytes" unless pixels.bytesize == width * height * 4
        client.call("surface.upload", { handle: }, payload: pixels)
        self
      end

      def blit_to(destination, x:, y:, source_rect: nil)
        parameters = { src: handle, dst: destination.handle,
                       dst_rect: { x:, y:, w: width, h: height } }
        parameters[:src_rect] = source_rect if source_rect
        client.call("surface.blit", parameters)
        destination
      end

      def destroy
        return self unless @owned
        client.call("surface.destroy", { handle: })
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
      end

      def present
        client.call("display.present")
        self
      end

      def events
        client.call("event.poll").fetch("events", [])
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
