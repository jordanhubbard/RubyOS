# frozen_string_literal: true

module RubyOS
  class Shell
    COMMANDS = {
      "help" => "show RubyOS shell commands",
      "version" => "show the running Ruby implementation",
      "devices" => "list devices and bound drivers",
      "tasks" => "list scheduler tasks and states"
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
        line = line.strip
        next if line.empty?
        break if line == "exit"

        if COMMANDS.key?(line)
          command(line)
        else
          evaluate(line)
        end
      end
      self
    end

    private

    def command(name)
      case name
      when "help"
        COMMANDS.each { |command, description| @output.puts format("%-9s %s", command, description) }
        @output.puts "exit      leave the console"
        @output.puts "Any other line is evaluated as Ruby."
      when "version"
        @output.puts RUBY_DESCRIPTION
      when "devices"
        devices = RubyOS::Kernel.state&.fetch(:bus, nil)
        devices&.each do |device|
          driver = device.driver&.class || "unbound"
          @output.puts "#{device.name}: #{driver}"
        end
      when "tasks"
        scheduler = RubyOS::Kernel.state&.fetch(:scheduler, nil)
        scheduler&.tasks&.each { |task| @output.puts "#{task.name}: #{task.state}" }
      end
    end

    def evaluate(source)
      result = eval(source, @context, "(rubyos)", 1)
      @output.puts "=> #{result.inspect}"
    rescue Exception => error
      @output.puts "#{error.class}: #{error.message}"
    end
  end
end
