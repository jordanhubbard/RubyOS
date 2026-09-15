# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_smp
      stats = Concurrency.stats
      RubyOS.invariant(stats.cpus == 4 && stats.online == 4, "not all ARM CPUs came online")
      RubyOS.invariant(stats.worker_selftests == 4, "native AP self-tests were incomplete")
      results = 3.times.map { |index| Concurrency.native_hash(0x5255_4259 + index, rounds: 20_000) }
      RubyOS.invariant(results.uniq.length == 3 && results.none?(&:zero?), "AP worker results invalid")
      HAL.serial_write("[RubyOS] SMP 4/4 with 3 native jobs: PASS\n")
      true
    end
  end
end
