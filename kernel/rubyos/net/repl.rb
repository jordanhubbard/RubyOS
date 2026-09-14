# frozen_string_literal: true

module RubyOS
  module Net
    class REPLServer
      attr_reader :port

      def initialize(stack, port: 17_011, context: TOPLEVEL_BINDING)
        @listener = stack.listen(port)
        @port = port
        @context = context
      end

      def serve_once(timeout_ms: 10_000)
        connection = @listener.accept(timeout_ms:)
        source = connection.read(timeout_ms:)
        response = begin
          "=> #{eval(source, @context).inspect}\n"
        rescue Exception => error
          "#{error.class}: #{error.message}\n"
        end
        connection.write(response)
        response
      end
    end
  end
end
