# frozen_string_literal: true

module RubyOS
  module Bridge
    class Surface
      attr_reader :client, :handle, :width, :height

      def initialize(client, handle:, width:, height:)
        @client = client
        @handle = Integer(handle)
        @width = Integer(width)
        @height = Integer(height)
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
