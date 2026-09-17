# frozen_string_literal: true
# Supervise only the QEMU/SDL children belonging to this checkout.
require "socket"
require "fileutils"

root = File.expand_path("..", __dir__)
Dir.chdir(root)
directory = File.join(root, "build", "run")
control = File.join(directory, "control.sock")
mode = ARGV.fetch(0, "console")
arch = ENV.fetch("RUBYOS_TARGET_ARCH") { RUBY_PLATFORM.match?(/aarch64|arm64/) ? "arm64" : "x86_64" }
abort "RUBYOS_TARGET_ARCH must be arm64 or x86_64" unless %w[arm64 x86_64].include?(arch)
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
serial_log = nil
serial_offset = 0
serial_tail = ""
fatal_markers = ["FATAL", "EXCEPTION", "ASSERT", "[BUG]"]
%w[INT TERM].each { |signal| Signal.trap(signal) { stopping = true } }
begin
  qemu = ENV["RUBYOS_QEMU_BIN"]
  command = if arch == "arm64"
    [qemu || "qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a72"]
  else
    [qemu || "qemu-system-x86_64", "-M", "pc"]
  end
  command += ["-m", "512M", "-display", "none", "-monitor", "none", "-no-reboot"]
  variant = mode == "console" ? "repl" : "desktop"
  image = "build/baremetal/rubyos-#{arch}-#{variant}/rubyos"
  command += arch == "arm64" ? ["-kernel", "#{image}.elf"] : ["-cdrom", "#{image}.iso"]
  if mode == "console"
    command += ["-serial", "stdio"]
    children << Process.spawn(*command)
  else
    port = Integer(ENV.fetch("RUBYOS_REMOTEOS_PORT", "17012"))
    abort "RUBYOS_REMOTEOS_PORT must be 1..65535" unless (1..65_535).cover?(port)
    # Refuse an occupied endpoint before starting a service that could attach
    # to somebody else's guest. QEMU will also reject a later bind race.
    TCPServer.open("127.0.0.1", port) { |probe| probe.close }
    network_device = arch == "arm64" ? "virtio-net-device" : "virtio-net-pci,disable-legacy=on"
    serial_log = File.join(directory, "serial.log")
    FileUtils.rm_f(serial_log)
    command += ["-serial", "file:#{serial_log}",
                "-netdev", "user,id=net,hostfwd=tcp:127.0.0.1:#{port}-:5001",
                "-device", "#{network_device},netdev=net,mac=52:54:00:12:34:57"]
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
    if serial_log && File.file?(serial_log)
      File.open(serial_log, "rb") do |stream|
        stream.seek(serial_offset)
        output = stream.read.to_s
        serial_offset = stream.pos
        scan = serial_tail + output
        tail_size = [fatal_markers.map(&:bytesize).max - 1, scan.bytesize].min
        serial_tail = scan.byteslice(scan.bytesize - tail_size, tail_size).to_s
        if fatal_markers.any? { |marker| scan.include?(marker) }
          warn "RubyOS guest reported a fatal error; see #{serial_log}"
          status = 1
          stopping = true
        end
      end
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
