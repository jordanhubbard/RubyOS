# frozen_string_literal: true
# Supervise only the QEMU/SDL children belonging to this checkout.
require "socket"
require "fileutils"

root = File.expand_path("..", __dir__)
Dir.chdir(root)
directory = File.join(root, "build", "run")
control = File.join(directory, "control.sock")
mode = ARGV.fetch(0, "console")
abort "usage: run.rb console|gui|stop" unless %w[console gui stop].include?(mode)

if mode == "stop"
  begin
    UNIXSocket.open(control) { |socket| socket.read }
    puts "RubyOS stopped"
  rescue Errno::ENOENT, Errno::ECONNREFUSED
    puts "RubyOS is not running"
  end
  exit
end

FileUtils.mkdir_p(directory)
lock = File.open(File.join(directory, "session.lock"), "w")
abort "RubyOS is already running in this checkout; use make stop" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
File.unlink(control) if File.socket?(control)
server = UNIXServer.new(control)
children = []
stopping = false
stop_client = nil
status = 0
%w[INT TERM].each { |signal| Signal.trap(signal) { stopping = true } }
begin
  command = ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a72", "-m", "512M",
             "-display", "none", "-monitor", "none", "-no-reboot"]
  if mode == "console"
    command += ["-serial", "stdio", "-kernel", "build/baremetal/rubyos-arm64-repl/rubyos.elf"]
    children << Process.spawn(*command)
  else
    port = Integer(ENV.fetch("RUBYOS_REMOTEOS_PORT", "17012"))
    abort "RUBYOS_REMOTEOS_PORT must be 1..65535" unless (1..65_535).cover?(port)
    # Refuse an occupied endpoint before starting a service that could attach
    # to somebody else's guest. QEMU will also reject a later bind race.
    TCPServer.open("127.0.0.1", port) { |probe| probe.close }
    command += ["-serial", "file:#{directory}/serial.log", "-kernel",
                "build/baremetal/rubyos-arm64-desktop/rubyos.elf",
                "-netdev", "user,id=net,hostfwd=tcp:127.0.0.1:#{port}-:5001",
                "-device", "virtio-net-device,netdev=net,mac=52:54:00:12:34:57"]
    children << Process.spawn(*command, in: File::NULL)
    service = ENV.fetch("REMOTEOS_SDL_BIN", "#{root}/services/remoteos-sdl/remoteos-sdl")
    environment = { "REMOTEOS_SDL_MODE" => ENV.fetch("REMOTEOS_SDL_MODE", "interactive") }
    children << Process.spawn(environment, service, "--connect-tcp", "127.0.0.1:#{port}",
                              "--connect-timeout-ms", "30000")
    puts "RubyOS desktop; guest log: #{directory}/serial.log"
  end
  until stopping
    if IO.select([server], nil, nil, 0.1)
      stop_client = server.accept
      stopping = true
    end
    children.dup.each do |pid|
      next unless Process.waitpid(pid, Process::WNOHANG)
      status = $?.success? ? 0 : 1
      children.delete(pid)
      stopping = true
    end
  end
ensure
  children.each { |pid| Process.kill("TERM", pid) rescue Errno::ESRCH }
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  until children.empty? || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    children.delete_if { |pid| Process.waitpid(pid, Process::WNOHANG) }
    sleep 0.05 unless children.empty?
  end
  children.each do |pid|
    Process.kill("KILL", pid) rescue Errno::ESRCH
    Process.waitpid(pid)
  end
  server.close
  File.unlink(control) if File.socket?(control)
  lock.close
  stop_client&.close
end
exit status
