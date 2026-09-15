# frozen_string_literal: true

module RubyOS
  module Debug
    module_function

    def snapshot(state = nil)
      state ||= RubyOS::Kernel.state if defined?(RubyOS::Kernel)
      state ||= {}
      scheduler = state[:scheduler]
      memory = state[:memory]&.snapshot
      cpus = Concurrency.stats
      {
        ruby: RUBY_DESCRIPTION,
        rubyos: RubyOS::VERSION,
        uptime_ms: state[:clock]&.milliseconds,
        scheduler: {
          ticks: scheduler&.ticks || 0,
          tasks: (scheduler&.tasks || []).map do |task|
            { pid: task.pid, name: task.name, state: task.state, ticks: task.ticks }.freeze
          end.freeze
        }.freeze,
        memory: memory && {
          total_bytes: memory.total_bytes,
          free_bytes: memory.free_bytes,
          used_bytes: memory.used_bytes
        }.freeze,
        concurrency: {
          cpus: cpus.cpus,
          online: cpus.online,
          worker_selftests: cpus.worker_selftests
        }.freeze
      }.freeze
    end
  end
end
