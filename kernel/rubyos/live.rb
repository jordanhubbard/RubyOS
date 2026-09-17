# frozen_string_literal: true

module RubyOS
  # Live Ruby facilities deliberately expose Ruby concepts rather than a
  # generic debugger facade: Modules are reload sandboxes, methods are patched
  # transactionally, and object graphs retain real class and ivar names.
  module Live
    EMBEDDED_SOURCES = {}.freeze unless const_defined?(:EMBEDDED_SOURCES, false)

    Reload = Data.define(:name, :application_class, :generation, :source_bytes, :path)
    Patch = Data.define(:target, :generation, :methods, :source)

    module_function

    def compile(source, filename = "(rubyos-live)")
      RubyVM::InstructionSequence.compile(String(source), filename, filename, 1)
    end

    module SourceArchive
      module_function

      def fetch(path)
        path = String(path)
        return EMBEDDED_SOURCES.fetch(path) if EMBEDDED_SOURCES.key?(path)

        root = File.expand_path("../..", __dir__)
        File.binread(File.join(root, path))
      rescue Errno::ENOENT
        raise KeyError, "source is not archived: #{path}"
      end

      def include?(path)
        EMBEDDED_SOURCES.key?(String(path)) ||
          File.file?(File.join(File.expand_path("../..", __dir__), String(path)))
      rescue NameError
        false
      end
    end

    # Evaluate one complete app source file under an isolated RubyOS namespace.
    # Constant lookup delegates to the running kernel for dependencies, while
    # class/module declarations create fresh values inside the sandbox. A failed
    # compile or evaluation therefore cannot mutate the live application class.
    class SourceSandbox
      attr_reader :rubyos

      def initialize(source, path)
        source = String(source)
        @root = Module.new
        @rubyos = Module.new
        running_rubyos = RubyOS
        @rubyos.define_singleton_method(:const_missing) do |name|
          running_rubyos.const_get(name, false)
        end
        declared_namespaces = source.scan(/^  module ([A-Z]\w*)\b/).flatten.uniq
        running_rubyos.constants(false).each do |name|
          next if declared_namespaces.include?(name.to_s)

          @rubyos.const_set(name, running_rubyos.const_get(name, false))
        end
        declared_constants = source.scan(/^    (?:class|module) ([A-Z]\w*)\b/).flatten
        declared_constants.concat(source.scan(/^    ([A-Z]\w*)\s*=/).flatten).uniq!
        declared_namespaces.each do |namespace_name|
          namespace = Module.new
          running_namespace = running_rubyos.const_get(namespace_name, false)
          namespace.define_singleton_method(:const_missing) do |name|
            running_namespace.const_get(name, false)
          end
          running_namespace.constants(false).each do |name|
            next if declared_constants.include?(name.to_s)

            namespace.const_set(name, running_namespace.const_get(name, false))
          end
          @rubyos.const_set(namespace_name, namespace)
        end
        @root.const_set(:RubyOS, @rubyos)
        @root.module_eval(source, String(path), 1)
      end

      def fetch(constant_path)
        String(constant_path).split("::").reject(&:empty?).inject(rubyos) do |scope, name|
          scope.const_get(name, false)
        end
      end
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
        vfs.write_file(path, source)
        registry.replace(name, application, source_path: path,
                          source_constant: constant.to_s)
        reload = Reload.new(name:, application_class:,
                            generation: history.length + 1,
                            source_bytes: source.bytesize, path:)
        history << reload
        reload
      end

      def reload(name, path:, constant: nil)
        entry = registry.entry(name)
        constant ||= entry.source_constant || :App
        source = vfs.read_file(path)
        return install(name, source:, path:, constant:) if constant.to_s == "App"

        install_archived(name, source:, path:, constant_path: constant)
      end

      def source_for(name)
        entry = registry.entry(name)
        overlay = overlay_path(name)
        vfs.read_file(overlay)
      rescue FS::NotFound
        SourceArchive.fetch(entry.source_path)
      end

      def overlay_path(name)
        slug = String(name).downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
        "/apps/#{slug}.rb"
      end

      def install_archived(name, source:, path:, constant_path:)
        name = String(name)
        source = String(source)
        Live.compile(source, path)
        application_class = SourceSandbox.new(source, path).fetch(constant_path)
        RubyOS.invariant(application_class <= Apps::Application,
                         "#{constant_path} must inherit RubyOS::Apps::Application")
        previous = registry.fetch(name)
        application = previous.rebuild_as(application_class)
        vfs.write_file(path, source)
        registry.replace(name, application)
        reload = Reload.new(name:, application_class:,
                            generation: history.length + 1,
                            source_bytes: source.bytesize, path:)
        history << reload
        reload
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
