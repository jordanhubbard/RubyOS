# frozen_string_literal: true

require "rubyos"

module RubyOS
  module Kernel
    module_function

    def state
      @state
    end

    def boot(output: $stdout)
      output.puts "RubyOS #{RubyOS::VERSION}"
      output.puts RUBY_DESCRIPTION

      bus = Bus.new
      console = bus.add(Device.new("COM1", kind: :serial, port: 0x3f8))
      bus.bind([SerialDriver])
      RubyOS.invariant(console.bound?, "boot console did not bind")

      scheduler = Scheduler.new
      trace = []
      2.times do |index|
        scheduler.spawn("ruby-task-#{index}") do
          trace << [index, :start]
          scheduler.yield_now
          trace << [index, :finish]
        end
      end
      scheduler.run

      filesystem = FS::TmpFS.new.seed(
        "tmp" => {},
        "home" => { "welcome.txt" => "Welcome to RubyOS. Ruby is the kernel.\n" },
        "apps" => {}
      )
      vfs = FS::VFS.new.mount("/", filesystem)

      output.puts "kernel: #{console.name} -> #{console.driver.class}"
      output.puts "kernel: fibers #{trace.inspect}"
      output.puts "kernel: Ruby owns the machine"
      @state = { bus:, scheduler:, trace:, vfs: }.freeze
    end
  end
end

RubyOS::Kernel.boot if $PROGRAM_NAME == __FILE__
