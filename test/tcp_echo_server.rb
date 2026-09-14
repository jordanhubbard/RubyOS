# frozen_string_literal: true

require "socket"

server = TCPServer.new("0.0.0.0", 18_081)
client = server.accept
payload = client.readpartial(4096)
client.write("echo:#{payload}")
client.close
server.close
