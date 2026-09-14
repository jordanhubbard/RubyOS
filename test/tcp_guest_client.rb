# frozen_string_literal: true

require "socket"

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
connect = lambda do
  socket = nil
  until socket
    begin
      socket = TCPSocket.new("127.0.0.1", 17_011)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.02
    end
  end
  socket
end

first = connect.call
second = connect.call
exchange = lambda do |socket, line|
  socket.write(line)
  socket.readpartial(4096)
end
response = exchange.call(first, 'local_only = 41')
abort "unexpected first response: #{response.inspect}" unless response == "=> 41\n"
response = exchange.call(second, 'defined?(local_only)')
abort "session namespace leaked: #{response.inspect}" unless response == "=> nil\n"
response = exchange.call(first, 'local_only + 1')
abort "first namespace was not retained: #{response.inspect}" unless response == "=> 42\n"
response = exchange.call(first, 'write /home/network.txt shared')
abort "TCP shell write failed: #{response.inspect}" unless response == "6 bytes\n"
response = exchange.call(second, 'cat /home/network.txt')
abort "TCP sessions do not share VFS: #{response.inspect}" unless response == "shared"
puts "multi-session Ruby REPL PASS"
first.close
second.close
