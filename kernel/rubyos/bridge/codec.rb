# frozen_string_literal: true

module RubyOS
  module Bridge
    module Codec
      module_function

      ESCAPES = { '"' => '\\"', "\\" => "\\\\", "\b" => "\\b",
                  "\f" => "\\f", "\n" => "\\n", "\r" => "\\r",
                  "\t" => "\\t" }.freeze

      def dump(value)
        case value
        when Hash
          "{" + value.map { |key, item| "#{dump(String(key))}:#{dump(item)}" }.join(",") + "}"
        when Array
          "[" + value.map { |item| dump(item) }.join(",") + "]"
        when String
          '"' + value.gsub(/["\\\b\f\n\r\t]/, ESCAPES) + '"'
        when Integer, Float
          value.to_s
        when true then "true"
        when false then "false"
        when nil then "null"
        else
          raise TypeError, "cannot encode #{value.class} as bridge JSON"
        end
      end

      def load(source)
        parser = Parser.new(String(source))
        value = parser.value
        parser.finish
        value
      end

      class Parser
        def initialize(source)
          @source = source
          @offset = 0
        end

        def value
          whitespace
          case peek
          when "{" then object
          when "[" then array
          when '"' then string
          when "t" then literal("true", true)
          when "f" then literal("false", false)
          when "n" then literal("null", nil)
          else number
          end
        end

        def finish
          whitespace
          raise Error.new(-1, "trailing bridge JSON") unless @offset == @source.bytesize
        end

        private

        def object
          take("{")
          result = {}
          whitespace
          return take("}") && result if peek == "}"
          loop do
            key = string
            whitespace
            take(":")
            result[key] = value
            whitespace
            return result if take_if("}")
            take(",")
          end
        end

        def array
          take("[")
          result = []
          whitespace
          return take("]") && result if peek == "]"
          loop do
            result << value
            whitespace
            return result if take_if("]")
            take(",")
          end
        end

        def string
          take('"')
          result = +""
          while (character = peek)
            @offset += 1
            return result if character == '"'
            unless character == "\\"
              result << character
              next
            end
            escape = peek
            @offset += 1
            result << case escape
                      when '"', "\\", "/" then escape
                      when "b" then "\b"
                      when "f" then "\f"
                      when "n" then "\n"
                      when "r" then "\r"
                      when "t" then "\t"
                      else raise Error.new(-1, "unsupported bridge JSON escape")
                      end
          end
          raise Error.new(-1, "unterminated bridge JSON string")
        end

        def number
          tail = @source.byteslice(@offset..)
          match = /\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/.match(tail)
          raise Error.new(-1, "invalid bridge JSON at #{@offset}") unless match
          @offset += match[0].bytesize
          match[0].match?(/[.eE]/) ? Float(match[0]) : Integer(match[0])
        end

        def literal(text, value)
          raise Error.new(-1, "invalid bridge JSON literal") unless @source.byteslice(@offset, text.bytesize) == text
          @offset += text.bytesize
          value
        end

        def whitespace
          @offset += 1 while (character = peek) && " \t\r\n".include?(character)
        end

        def peek
          return nil if @offset >= @source.bytesize

          @source.byteslice(@offset, 1)
        end

        def take(expected)
          raise Error.new(-1, "expected #{expected.inspect} in bridge JSON") unless take_if(expected)
          expected
        end

        def take_if(expected)
          whitespace
          return false unless peek == expected
          @offset += 1
          true
        end
      end
    end
  end
end
