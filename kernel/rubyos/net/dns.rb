# frozen_string_literal: true

module RubyOS
  module Net
    class DNSMessage
      attr_reader :identifier, :flags, :answers

      def self.query(identifier, name)
        labels = name.split(".")
        raise ArgumentError, "invalid DNS name" if labels.empty? || labels.any? { |label| label.empty? || label.bytesize > 63 }
        encoded = labels.map { |label| [label.bytesize].pack("C") + label }.join + "\0"
        [identifier, 0x0100, 1, 0, 0, 0].pack("n6") + encoded + [1, 1].pack("nn")
      end

      def initialize(bytes)
        @bytes = String(bytes).b
        raise ArgumentError, "DNS message is shorter than 12 bytes" if @bytes.bytesize < 12
        @identifier, @flags, questions, answer_count, = @bytes.unpack("n6")
        raise Error, "DNS server returned error #{@flags & 0x0f}" unless (@flags & 0x0f).zero?
        offset = 12
        questions.times do
          _, offset = decode_name(offset)
          offset += 4
          raise ArgumentError, "truncated DNS question" if offset > @bytes.bytesize
        end
        @answers = []
        answer_count.times do
          name, offset = decode_name(offset)
          raise ArgumentError, "truncated DNS answer" if offset + 10 > @bytes.bytesize
          type, klass, ttl, length = @bytes.byteslice(offset, 10).unpack("nnNn")
          offset += 10
          raise ArgumentError, "truncated DNS record" if offset + length > @bytes.bytesize
          data = @bytes.byteslice(offset, length)
          offset += length
          @answers << { name:, type:, class: klass, ttl:, data: }
        end
      end

      def addresses
        answers.filter_map do |answer|
          IPv4Address.new(answer[:data]) if answer[:type] == 1 && answer[:class] == 1 && answer[:data].bytesize == 4
        end
      end

      private

      def decode_name(offset, visited = {})
        raise ArgumentError, "DNS compression loop" if visited[offset]
        visited[offset] = true
        labels = []
        consumed = nil
        loop do
          raise ArgumentError, "truncated DNS name" if offset >= @bytes.bytesize
          length = @bytes.getbyte(offset)
          if (length & 0xc0) == 0xc0
            raise ArgumentError, "truncated DNS pointer" if offset + 1 >= @bytes.bytesize
            pointer = ((length & 0x3f) << 8) | @bytes.getbyte(offset + 1)
            consumed ||= offset + 2
            suffix, = decode_name(pointer, visited)
            labels << suffix unless suffix.empty?
            break
          end
          offset += 1
          if length.zero?
            consumed ||= offset
            break
          end
          raise ArgumentError, "invalid DNS label" if length > 63 || offset + length > @bytes.bytesize
          labels << @bytes.byteslice(offset, length)
          offset += length
        end
        [labels.join("."), consumed]
      end
    end

    class DNSClient
      def initialize(stack, server)
        @stack = stack
        @server = server
        @identifier = 0x5255
      end

      def resolve(name, timeout_ms: 5_000)
        @identifier = (@identifier + 1) & 0xffff
        response = @stack.udp_exchange(@server, 53, DNSMessage.query(@identifier, name),
                                       source_port: 53_000, timeout_ms:)
        message = DNSMessage.new(response)
        raise Error, "mismatched DNS transaction" unless message.identifier == @identifier
        message.addresses.first || raise(Error, "DNS response has no IPv4 address for #{name}")
      end
    end
  end
end
