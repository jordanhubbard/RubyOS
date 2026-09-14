# frozen_string_literal: true

require "socket"

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
socket = nil
until socket
  begin
    socket = TCPSocket.new("127.0.0.1", 17_011)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.02
  end
end
socket.write("RubyOS::VERSION.split('.').map(&:to_i).sum + 3")
response = socket.readpartial(4096)
abort "unexpected RubyOS response: #{response.inspect}" unless response == "=> 4\n"
puts response
socket.close
