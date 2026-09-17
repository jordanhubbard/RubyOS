# frozen_string_literal: true

module RubyOS
  class Shell
    COMMANDS = {
      "help" => "show RubyOS shell commands",
      "ruby" => "show the interactive Ruby runtime",
      "version" => "show the running Ruby implementation",
      "devices" => "list devices and bound drivers",
      "tasks" => "list scheduler tasks and states",
      "debug" => "show a machine-readable kernel snapshot",
      "uptime" => "show monotonic uptime in milliseconds",
      "time" => "show or set the session clock: time [HH:MM:SS|clear]",
      "sleep" => "sleep using the kernel timer: sleep milliseconds",
      "ls" => "list a VFS directory: ls [path]",
      "cat" => "read a VFS file: cat path",
      "write" => "replace a VFS file: write path text",
      "mkdir" => "create a VFS directory: mkdir path",
      "rm" => "remove a VFS file or empty directory: rm path",
      "truncate" => "resize a VFS file: truncate path size"
    }.freeze

    def initialize(input: nil, output: $stdout, context: TOPLEVEL_BINDING)
      @input = input || -> { RubyOS::HAL.serial_readline }
      @output = output
      @context = context
    end

    def run
      @output.puts "RubyOS console -- Ruby is the kernel.  Type help."
      loop do
        RubyOS::HAL.serial_write("rubyos> ") if defined?(RubyOS::HAL)
        line = @input.call
        break if line.nil?
        break if execute_line(line) == :exit
      end
      self
    end

    def execute_line(line)
      line = String(line).strip
      return :continue if line.empty?
      return :exit if line == "exit"
      name, *arguments = line.split(" ", 3)
      COMMANDS.key?(name) ? command(name, arguments) : evaluate(line)
      :continue
    end

    private

    def command(name, arguments)
      case name
      when "help"
        COMMANDS.each { |command, description| @output.puts format("%-9s %s", command, description) }
        @output.puts "exit      leave the console"
        @output.puts "Any other line is evaluated as Ruby."
      when "version"
        @output.puts RUBY_DESCRIPTION
      when "ruby"
        @output.puts RUBY_DESCRIPTION
        @output.puts "Ruby is already live here; enter any Ruby expression at this prompt."
      when "devices"
        devices = RubyOS::Kernel.state&.fetch(:bus, nil)
        devices&.each do |device|
          driver = device.driver&.class || "unbound"
          @output.puts "#{device.name}: #{driver}"
        end
      when "tasks"
        scheduler = RubyOS::Kernel.state&.fetch(:scheduler, nil)
        scheduler&.tasks&.each { |task| @output.puts "#{task.name}: #{task.state}" }
      when "debug"
        @output.puts RubyOS::Debug.snapshot.inspect
      when "uptime"
        @output.puts "#{clock.milliseconds} ms"
      when "time"
        set_time(arguments.first) unless arguments.empty?
        @output.puts clock.format_hms
      when "sleep"
        duration = Integer(arguments.fetch(0))
        clock.sleep(duration)
        @output.puts "slept #{duration} ms"
      when "ls"
        path = arguments.first || "/"
        @output.puts filesystem.readdir(path).reject { |entry| [".", ".."].include?(entry) }.join("  ")
      when "cat"
        @output.write(filesystem.read_file(arguments.fetch(0)))
      when "write"
        filesystem.write_file(arguments.fetch(0), arguments.fetch(1, ""))
        @output.puts "#{arguments.fetch(1, "").bytesize} bytes"
      when "mkdir"
        filesystem.mkdir(arguments.fetch(0))
        @output.puts "created #{arguments.fetch(0)}"
      when "rm"
        filesystem.unlink(arguments.fetch(0))
        @output.puts "removed #{arguments.fetch(0)}"
      when "truncate"
        filesystem.truncate(arguments.fetch(0), Integer(arguments.fetch(1)))
        @output.puts "truncated #{arguments.fetch(0)} to #{arguments.fetch(1)} bytes"
      end
    rescue FS::Error, ArgumentError, IndexError => error
      @output.puts "#{error.class}: #{error.message}"
    end

    def evaluate(source)
      result = eval(source, @context, "(rubyos)", 1)
      @output.puts "=> #{result.inspect}"
    rescue Exception => error
      @output.puts "#{error.class}: #{error.message}"
    end

    def filesystem
      RubyOS::Kernel.state.fetch(:vfs)
    end

    def clock
      RubyOS::Kernel.state.fetch(:clock)
    end

    def set_time(value)
      return clock.clear_wall_clock if value == "clear"

      parts = value.split(":").map { |part| Integer(part) }
      raise ArgumentError, "expected HH:MM[:SS]" unless (2..3).cover?(parts.length)
      clock.set_hms(parts.fetch(0), parts.fetch(1), parts.fetch(2, 0))
    end
  end
end
