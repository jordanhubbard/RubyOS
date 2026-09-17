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

      retired = scheduler.spawn("ruby-retired") { raise "retired task resumed" }
      RubyOS.invariant(scheduler.kill(retired.pid), "ready task was not killed")
      RubyOS.invariant(scheduler.reap(retired).equal?(retired), "killed task was not reaped")
      scheduler.spawn("ruby-request", auto_reap: true) { :served }
      scheduler.run
      RubyOS.invariant(scheduler.tasks.none? { |task| task.name == "ruby-request" },
                       "short-lived task was not auto-reaped")

      timer_trace = []
      scheduler.spawn("ruby-timer") do
        timer_trace << :sleep
        scheduler.sleep_for(2)
        timer_trace << :wake
      end
      scheduler.run

      clock = Timekeeper.new
      memory = Memory::Manager.system
      if defined?(HAL) && HAL.respond_to?(:heap_page_probe)
        RubyOS.invariant(HAL.heap_page_probe, "native page allocation/release failed")
      end
      probe_frame = memory.allocate
      memory.release(probe_frame)
      # Global heap snapshots include allocations by the Ruby VM itself.
      # The native probe above checks exact reclamation without VM noise.
      RubyOS.invariant(probe_frame.released?, "page frame release not recorded")

      filesystem = FS::TmpFS.new.seed(
        "tmp" => {},
        "home" => { "welcome.txt" => "Welcome to RubyOS. Ruby is the kernel.\n" },
        "apps" => {},
        "examples" => Examples.files
      )
      vfs = FS::VFS.new.mount("/", filesystem)

      output.puts "kernel: #{console.name} -> #{console.driver.class}"
      output.puts "kernel: devices #{bus.topology.join(', ')}"
      output.puts "kernel: fibers #{trace.inspect}"
      output.puts "kernel: timer #{timer_trace.inspect}"
      output.puts "kernel: scheduler lifecycle kill/reap/auto-reap"
      output.puts "kernel: memory #{memory.snapshot.used_bytes}/#{memory.snapshot.total_bytes} bytes"
      output.puts "kernel: Ruby owns the machine"
      @state = { bus:, scheduler:, trace:, timer_trace:, vfs:, clock:, memory: }.freeze
    end
  end
end

RubyOS::Kernel.boot if $PROGRAM_NAME == __FILE__
