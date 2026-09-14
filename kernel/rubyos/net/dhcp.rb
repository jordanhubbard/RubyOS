# frozen_string_literal: true

module RubyOS
  module Net
    DHCPLease = Data.define(:address, :gateway, :netmask, :dns, :server, :lease_seconds)

    class DHCPMessage
      MAGIC = 0x63825363
      DISCOVER = 1
      OFFER = 2
      REQUEST = 3
      ACK = 5

      attr_reader :transaction, :client_mac, :your_address, :options

      def initialize(transaction:, client_mac:, your_address: IPv4Address.new("0.0.0.0"), options: {})
        @transaction = transaction
        @client_mac = client_mac
        @your_address = your_address
        @options = options
      end

      def self.decode(bytes)
        raise ArgumentError, "DHCP packet is shorter than 240 bytes" if bytes.bytesize < 240
        raise ArgumentError, "not a DHCP reply" unless bytes.getbyte(0) == 2
        raise ArgumentError, "bad DHCP magic" unless bytes.byteslice(236, 4).unpack1("N") == MAGIC
        transaction = bytes.byteslice(4, 4).unpack1("N")
        address = IPv4Address.new(bytes.byteslice(16, 4))
        mac = MACAddress.new(bytes.byteslice(28, 6))
        new(transaction:, client_mac: mac, your_address: address,
            options: decode_options(bytes.byteslice(240..)))
      end

      def self.decode_options(bytes)
        options = {}
        offset = 0
        while offset < bytes.bytesize
          code = bytes.getbyte(offset)
          offset += 1
          next if code.zero?
          break if code == 255
          raise ArgumentError, "truncated DHCP option" if offset >= bytes.bytesize
          length = bytes.getbyte(offset)
          offset += 1
          raise ArgumentError, "truncated DHCP option value" if offset + length > bytes.bytesize
          options[code] = bytes.byteslice(offset, length)
          offset += length
        end
        options
      end

      def encode
        header = [1, 1, 6, 0, transaction, 0, 0].pack("CCCCNnn")
        header << "\0".b * 16
        header << client_mac.bytes << "\0".b * 10
        header << "\0".b * 192
        header << [MAGIC].pack("N")
        options.each do |code, value|
          value = String(value).b
          header << [code, value.bytesize].pack("CC") << value
        end
        header << "\xff".b
      end

      def message_type
        options.fetch(53).getbyte(0)
      end

      def option_address(code, fallback = nil)
        value = options[code]
        value && value.bytesize >= 4 ? IPv4Address.new(value.byteslice(0, 4)) : fallback
      end

      def option_u32(code, fallback = 0)
        value = options[code]
        value&.bytesize == 4 ? value.unpack1("N") : fallback
      end
    end

    class DHCPClient
      CLIENT_PORT = 68
      SERVER_PORT = 67
      BROADCAST_IP = IPv4Address.new("255.255.255.255")
      ZERO_IP = IPv4Address.new("0.0.0.0")

      def initialize(device, transaction: 0x5255_4259)
        @device = device
        @transaction = transaction
      end

      def acquire(timeout_ms: 5_000)
        discover = DHCPMessage.new(transaction: @transaction, client_mac: @device.mac,
                                   options: { 53 => [DHCPMessage::DISCOVER].pack("C"),
                                              55 => [1, 3, 6, 51].pack("C*") })
        send_message(discover)
        offer = wait_for(DHCPMessage::OFFER, timeout_ms)
        raise Error, "DHCP offer timed out" unless offer
        server = offer.option_address(54, offer.option_address(3, ZERO_IP))
        request = DHCPMessage.new(transaction: @transaction, client_mac: @device.mac,
                                  options: { 53 => [DHCPMessage::REQUEST].pack("C"),
                                             50 => offer.your_address.bytes,
                                             54 => server.bytes,
                                             55 => [1, 3, 6, 51].pack("C*") })
        send_message(request)
        acknowledgment = wait_for(DHCPMessage::ACK, timeout_ms)
        raise Error, "DHCP acknowledgment timed out" unless acknowledgment
        DHCPLease.new(acknowledgment.your_address,
                      acknowledgment.option_address(3, ZERO_IP),
                      acknowledgment.option_address(1, IPv4Address.new("255.255.255.0")),
                      acknowledgment.option_address(6, server), server,
                      acknowledgment.option_u32(51))
      end

      private

      def send_message(message)
        udp = UDPSegment.new(CLIENT_PORT, SERVER_PORT, message.encode)
        packet = IPv4Packet.new(ZERO_IP, BROADCAST_IP, IPv4Packet::UDP,
                                udp.encode(source_ip: ZERO_IP, destination_ip: BROADCAST_IP),
                                64, 0, 0)
        frame = EthernetFrame.new(MACAddress.broadcast, @device.mac,
                                  EthernetFrame::IPV4, packet.encode)
        @device.send(frame.encode)
      end

      def wait_for(type, timeout_ms)
        deadline = RubyOS::HAL.monotonic_ns + timeout_ms * 1_000_000
        while RubyOS::HAL.monotonic_ns < deadline
          bytes = @device.receive
          next unless bytes
          frame = EthernetFrame.decode(bytes)
          next unless frame.ethertype == EthernetFrame::IPV4
          packet = IPv4Packet.decode(frame.payload)
          next unless packet.protocol == IPv4Packet::UDP
          segment = UDPSegment.decode(packet.payload)
          next unless segment.destination_port == CLIENT_PORT && segment.source_port == SERVER_PORT
          message = DHCPMessage.decode(segment.payload)
          next unless message.transaction == @transaction && message.client_mac == @device.mac
          return message if message.message_type == type
        end
        nil
      end
    end
  end
end
