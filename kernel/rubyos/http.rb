# frozen_string_literal: true

module RubyOS
  module HTTP
    Request = Data.define(:method, :target, :version, :headers, :body)

    class Parser
      def self.parse(bytes)
        head, separator, body = String(bytes).b.partition("\r\n\r\n")
        raise ArgumentError, "incomplete HTTP headers" if separator.empty?
        request_line, *header_lines = head.split("\r\n")
        method, target, version = request_line.to_s.split(" ", 3)
        raise ArgumentError, "invalid HTTP request line" unless method && target && version&.start_with?("HTTP/")
        headers = header_lines.to_h do |line|
          name, value = line.split(":", 2)
          raise ArgumentError, "invalid HTTP header" unless value
          [name.downcase, value.strip]
        end
        length = Integer(headers.fetch("content-length", "0"), 10)
        raise ArgumentError, "incomplete HTTP body" if body.bytesize < length
        Request.new(method:, target:, version:, headers: headers.freeze,
                    body: body.byteslice(0, length).freeze)
      end
    end

    class Router
      def initialize
        @routes = {}
      end

      def get(path, &handler)
        raise ArgumentError, "route block required" unless handler
        @routes[["GET", String(path)]] = handler
        self
      end

      def call(environment)
        handler = @routes[[environment.fetch("REQUEST_METHOD"),
                           environment.fetch("PATH_INFO")]]
        return [404, { "content-type" => "text/plain" }, ["Not Found\n"]] unless handler
        value = handler.call(environment)
        value.is_a?(Array) && value.length == 3 ? value :
          [200, { "content-type" => "text/plain" }, [String(value)]]
      end
    end

    class Server
      REASONS = { 200 => "OK", 201 => "Created", 400 => "Bad Request",
                  404 => "Not Found", 500 => "Internal Server Error" }.freeze
      MAX_REQUEST_BYTES = 64 * 1024

      attr_reader :app

      def initialize(app)
        @app = app
      end

      def serve_once(listener, timeout_ms: 30_000)
        connection = listener.accept(timeout_ms:)
        request = read_request(connection, timeout_ms:)
        status, headers, body = app.call(environment(request))
        connection.write(response(status, headers, body))
        { method: request.method, target: request.target, status: Integer(status) }.freeze
      rescue Exception => error
        connection&.write(response(500, { "content-type" => "text/plain" },
                                   ["#{error.class}: #{error.message}\n"]))
        raise
      ensure
        connection&.close
      end

      private

      def read_request(connection, timeout_ms:)
        bytes = +"".b
        until (boundary = bytes.index("\r\n\r\n"))
          bytes << connection.read(timeout_ms:)
          raise RubyOS::Error, "HTTP request exceeds #{MAX_REQUEST_BYTES} bytes" if bytes.bytesize > MAX_REQUEST_BYTES
        end
        head = bytes.byteslice(0, boundary + 4)
        content_length = head[/\r\ncontent-length:\s*(\d+)/i, 1].to_i
        required = boundary + 4 + content_length
        while bytes.bytesize < required
          bytes << connection.read(timeout_ms:)
          raise RubyOS::Error, "HTTP request exceeds #{MAX_REQUEST_BYTES} bytes" if bytes.bytesize > MAX_REQUEST_BYTES
        end
        Parser.parse(bytes.byteslice(0, required))
      end

      def environment(request)
        path, query = request.target.split("?", 2)
        env = {
          "REQUEST_METHOD" => request.method,
          "PATH_INFO" => path,
          "QUERY_STRING" => query.to_s,
          "SERVER_PROTOCOL" => request.version,
          "rack.version" => [3, 0],
          "rack.url_scheme" => "http",
          "rack.input" => request.body,
          "rubyos.request" => request
        }
        request.headers.each { |name, value| env["HTTP_#{name.upcase.tr('-', '_')}"] = value }
        env.freeze
      end

      def response(status, headers, body)
        status = Integer(status)
        body = body.respond_to?(:each) ? body.to_a.join : String(body)
        normalized = headers.transform_keys { |name| String(name).downcase }
        normalized["content-length"] = body.bytesize.to_s
        normalized["connection"] ||= "close"
        head = +"HTTP/1.1 #{status} #{REASONS.fetch(status, "Status")}\r\n"
        normalized.each { |name, value| head << "#{name}: #{value}\r\n" }
        head << "\r\n" << body
      end
    end

    class HelloApp
      def call(environment)
        body = "RubyOS says hello from #{environment.fetch('PATH_INFO')}\n"
        [200, { "content-type" => "text/plain; charset=utf-8" }, [body]]
      end
    end
  end
end
