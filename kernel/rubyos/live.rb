# frozen_string_literal: true

module RubyOS
  # Live Ruby facilities deliberately expose Ruby concepts rather than a
  # generic debugger facade: Modules are reload sandboxes, methods are patched
  # transactionally, and object graphs retain real class and ivar names.
  module Live
    Reload = Data.define(:name, :application_class, :generation, :source_bytes)
    Patch = Data.define(:target, :generation, :methods, :source)

    module_function

    def compile(source, filename = "(rubyos-live)")
      RubyVM::InstructionSequence.compile(String(source), filename, filename, 1)
    end

    class Runtime
      attr_reader :vfs, :registry, :history

      def initialize(vfs:, registry:, kernel: RubyOS::Kernel)
        @vfs = vfs
        @registry = registry
        @kernel = kernel
        @history = []
      end

      def install(name, source:, path: nil, constant: :App)
        name = String(name)
        path ||= "/apps/#{name.downcase.gsub(/[^a-z0-9]+/, "_")}.rb"
        source = String(source)
        Live.compile(source, path)
        sandbox = Module.new
        sandbox.module_eval(source, path, 1)
        application_class = sandbox.const_get(constant, false)
        RubyOS.invariant(application_class <= Apps::Application,
                         "#{constant} must inherit RubyOS::Apps::Application")
        application = application_class.new(kernel: @kernel)
        registry.replace(name, application)
        vfs.write_file(path, source)
        reload = Reload.new(name:, application_class:,
                            generation: history.length + 1,
                            source_bytes: source.bytesize)
        history << reload
        reload
      end

      def reload(name, path:, constant: :App)
        install(name, source: vfs.read_file(path), path:, constant:)
      end
    end

    class ClassEditor
      attr_reader :history

      def initialize
        @history = []
      end

      def apply(target, source, filename: "(rubyos-class-patch)")
        raise TypeError, "patch target must be a Module" unless target.is_a?(Module)
        source = String(source)
        Live.compile(source, filename)
        before = snapshot(target)
        target.class_eval(source, filename, 1)
        changed = (declared_methods(target) | before.keys).select do |name|
          !before.key?(name) || target.instance_method(name) != before.fetch(name).fetch(:method)
        end
        patch = Patch.new(target:, generation: history.length + 1,
                          methods: changed.freeze, source: source.freeze)
        history << patch
        patch
      rescue Exception
        restore(target, before) if before
        raise
      end

      private

      def declared_methods(target)
        target.public_instance_methods(false) |
          target.protected_instance_methods(false) |
          target.private_instance_methods(false)
      end

      def snapshot(target)
        declared_methods(target).to_h do |name|
          visibility = if target.private_instance_methods(false).include?(name)
                         :private
                       elsif target.protected_instance_methods(false).include?(name)
                         :protected
                       else
                         :public
                       end
          [name, { method: target.instance_method(name), visibility: }]
        end
      end

      def restore(target, before)
        (declared_methods(target) - before.keys).each do |name|
          target.send(:remove_method, name)
        end
        before.each do |name, entry|
          target.send(:define_method, name, entry.fetch(:method))
          target.send(entry.fetch(:visibility), name)
        end
      end
    end
  end

  module Introspection
    module_function

    def class_shape(type)
      {
        name: type.name,
        ancestors: type.ancestors.map(&:name),
        public_methods: type.public_instance_methods(false).sort,
        protected_methods: type.protected_instance_methods(false).sort,
        private_methods: type.private_instance_methods(false).sort,
        constants: type.constants(false).sort
      }.freeze
    end

    def fibers(scheduler)
      scheduler.tasks.map do |task|
        { pid: task.pid, name: task.name, state: task.state,
          alive: task.fiber.alive?, ticks: task.ticks,
          fiber_id: task.fiber.object_id }.freeze
      end.freeze
    end

    def drivers(bus)
      bus.map do |device|
        { name: device.name, properties: device.properties,
          resources: device.resources.map { |resource| resource.class.name },
          driver: device.driver&.class&.name,
          bound: device.bound? }.freeze
      end.freeze
    end

    def heap_summary(limit: 16)
      counts = Hash.new(0)
      ObjectSpace.each_object { |object| counts[object.class.name || object.class.to_s] += 1 }
      counts.sort_by { |_, count| -count }.first(Integer(limit)).to_h.freeze
    end

    def object_graph(*roots, depth: 2, limit: 128)
      queue = roots.flatten.map { |object| [object, 0] }
      seen = {}
      nodes = []
      edges = []
      until queue.empty? || nodes.length >= limit
        object, level = queue.shift
        next if seen.key?(object.object_id)
        seen[object.object_id] = true
        nodes << { id: object.object_id, class: object.class.name,
                   label: label(object) }.freeze
        next if level >= depth
        references(object).each do |name, child|
          next if immediate?(child)
          edges << { from: object.object_id, to: child.object_id, name: }.freeze
          queue << [child, level + 1]
        end
      end
      { nodes: nodes.freeze, edges: edges.freeze, truncated: !queue.empty? }.freeze
    end

    def references(object)
      refs = object.instance_variables.map do |name|
        [name.to_s, object.instance_variable_get(name)]
      end
      case object
      when Array
        object.each_with_index { |value, index| refs << ["[#{index}]", value] }
      when Hash
        object.each_with_index do |(key, value), index|
          refs << ["key[#{index}]", key] << ["value[#{index}]", value]
        end
      end
      refs
    rescue Exception
      []
    end

    def immediate?(object)
      object.nil? || object == true || object == false ||
        object.is_a?(Numeric) || object.is_a?(Symbol)
    end

    def label(object)
      text = object.inspect
      text.length > 80 ? "#{text[0, 77]}..." : text
    rescue Exception
      "#<#{object.class}>"
    end
  end
end
