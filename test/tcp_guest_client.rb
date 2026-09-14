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
first.write('local_only = 41')
response = first.readpartial(4096)
abort "unexpected first response: #{response.inspect}" unless response == "=> 41\n"
second.write('defined?(local_only)')
response = second.readpartial(4096)
abort "session namespace leaked: #{response.inspect}" unless response == "=> nil\n"
first.write('local_only + 1')
response = first.readpartial(4096)
abort "first namespace was not retained: #{response.inspect}" unless response == "=> 42\n"
puts "multi-session Ruby REPL PASS"
first.close
second.close
