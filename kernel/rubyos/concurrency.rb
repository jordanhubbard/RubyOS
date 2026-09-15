# frozen_string_literal: true

module RubyOS
  module Concurrency
    Stats = Data.define(:cpus, :online, :worker_selftests)

    module_function

    def stats
      if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:cpu_count)
        Stats.new(cpus: HAL.cpu_count, online: HAL.online_cpus,
                  worker_selftests: HAL.worker_selftests)
      else
        Stats.new(cpus: 1, online: 1, worker_selftests: 1)
      end
    end

    def native_hash(value, rounds: 10_000)
      raise RubyOS::Error, "native AP workers are unavailable" unless HAL.respond_to?(:worker_hash)

      HAL.worker_hash(Integer(value), Integer(rounds))
    end
  end
end
