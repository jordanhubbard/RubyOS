# frozen_string_literal: true

module RubyOS
  class Shell
    COMMANDS = {
      "help" => "show RubyOS shell commands",
      "ruby" => "show the interactive Ruby runtime",
      "apps" => "list desktop applications, Ruby demos, and games",
      "examples" => "list learning tracks: examples [track]",
      "example" => "run a Ruby lesson: example [track/]name",
      "version" => "show the running Ruby implementation",
      "devices" => "list devices and bound drivers",
      "tasks" => "list scheduler task PIDs, states, and ticks",
      "kill" => "cancel a scheduler task: kill PID",
      "reap" => "remove a completed task record: reap PID",
      "debug" => "show a machine-readable kernel snapshot",
      "sysinfo" => "show RubyOS, CPU, scheduler, and working-directory status",
      "netstat" => "show configured network interfaces",
      "uptime" => "show monotonic uptime in milliseconds",
      "time" => "show or set the session clock: time [HH:MM:SS|clear]",
      "sleep" => "sleep using the kernel timer: sleep milliseconds",
      "pwd" => "print the current VFS directory",
      "cd" => "change the current VFS directory: cd [path]",
      "ls" => "list a VFS directory: ls [path]",
      "cat" => "read VFS files: cat path [path ...]",
      "cp" => "copy a VFS file: cp source destination",
      "mv" => "move a VFS file: mv source destination",
      "write" => "replace a VFS file: write path text",
      "mkdir" => "create a VFS directory: mkdir path",
      "rm" => "remove a VFS file or empty directory: rm path",
      "truncate" => "resize a VFS file: truncate path size",
      "run" => "evaluate a Ruby source file: run path",
      "desktop" => "list or launch desktop applications: desktop [name]",
      "ed" => "open a VFS file in the graphical Editor: ed [path]",
      "ftp" => "transfer a file: ftp get DST [PORT] | put SRC [HOST] [PORT]"
    }.freeze

    attr_reader :cwd

    def initialize(input: nil, output: $stdout, context: TOPLEVEL_BINDING,
                   network: nil, desktop: nil, cwd: "/home")
      @input = input || -> { RubyOS::HAL.serial_readline }
      @output = output
      @context = context
      @network = network
      @desktop = desktop
      @cwd = normalize_path(cwd)
    end

    def run
      @output.puts "RubyOS console -- Ruby is the kernel.  Type help."
      pending = +""
      loop do
        RubyOS::HAL.serial_write(pending.empty? ? "rubyos> " : "....> ") if defined?(RubyOS::HAL)
        line = @input.call
        break if line.nil?
        source = pending.empty? ? String(line) : "#{pending}\n#{line}"
        unless source_complete?(source)
          pending = source
          next
        end
        pending.clear
        break if execute_line(source) == :exit
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

    def source_complete?(source)
      source = String(source)
      command_name = source.lstrip.split(/\s+/, 2).first
      return true if !source.include?("\n") && (COMMANDS.key?(command_name) || command_name == "exit")

      RubyVM::InstructionSequence.compile(source)
      true
    rescue SyntaxError => error
      !error.message.match?(/unexpected end-of-input|unterminated|embedded document meets end of file|expected an? .?end.? to close/)
    end

    def completion_candidates(source)
      source = String(source)
      token = source[/[^\s]*\z/].to_s
      prefix = source.delete_suffix(token)
      candidates = if prefix.empty?
                     (COMMANDS.keys + ["exit"] + Object.constants.map(&:to_s))
                       .grep(/\A#{Regexp.escape(token)}/)
                   elsif token.include?(".")
                     receiver_name, method_prefix = token.split(".", 2)
                     receiver = completion_receiver(receiver_name)
                     receiver ? receiver.public_methods.map { |name| "#{receiver_name}.#{name}" }
                             .grep(/\A#{Regexp.escape(receiver_name)}\.#{Regexp.escape(method_prefix)}/) : []
                   else
                     path_candidates(token)
                   end
      candidates.uniq.sort.map { |candidate| prefix + candidate }
    end

    def complete(source)
      candidates = completion_candidates(source)
      return [String(source), []] if candidates.empty?

      common = candidates.reduce { |left, right| left[0, left.chars.zip(right.chars).take_while { |a, b| a == b }.length] }
      completed = candidates.length == 1 ? "#{candidates.first} " : common
      [completed, candidates]
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
      when "apps"
        Apps::Catalog.build(kernel: RubyOS::Kernel).entries.each do |entry|
          @output.puts format("%-5s %-18s %s", entry.category, entry.name, entry.description)
        end
        @output.puts "Start the graphical catalog with make run-gui, then open Apps."
      when "examples"
        if arguments.empty?
          @output.puts "RubyOS learning tracks in /examples:"
          Examples.tracks.each do |track|
            count = Examples.lessons_for(track.name).length
            suffix = count.positive? ? " (#{count})" : ""
            @output.puts format("  %-13s %s%s", track.name, track.summary, suffix)
          end
          @output.puts "Start:  example start_here/hello_kernel"
          @output.puts "Browse: examples language  or  cat /examples/README.txt"
        else
          track = Examples.fetch_track(arguments.fetch(0))
          lessons = Examples.lessons_for(track.name)
          @output.puts "Examples in /examples/#{track.name}:"
          if lessons.empty?
            @output.puts "  Open the #{track.name} category from Apps."
          else
            lessons.each do |lesson|
              @output.puts format("  %-22s %s", lesson.name, lesson.summary)
            end
            @output.puts "Guide: cat /examples/#{track.name}/README.txt"
          end
        end
      when "example"
        name = arguments.fetch(0)
        result = Examples.run(name, context: @context)
        @output.puts "=> #{result.inspect}"
      when "devices"
        devices = RubyOS::Kernel.state&.fetch(:bus, nil)
        devices&.each do |device|
          driver = device.driver&.class || "unbound"
          @output.puts "#{device.name}: #{driver}"
        end
      when "tasks"
        scheduler = RubyOS::Kernel.state&.fetch(:scheduler, nil)
        scheduler&.tasks&.each do |task|
          @output.puts format("%4d  %-18s %-9s ticks=%d",
                              task.pid, task.name, task.state, task.ticks)
        end
      when "kill"
        pid = Integer(arguments.fetch(0))
        scheduler = RubyOS::Kernel.state.fetch(:scheduler)
        @output.puts(scheduler.kill(pid) ? "killed #{pid}" : "no live task #{pid}")
      when "reap"
        pid = Integer(arguments.fetch(0))
        scheduler = RubyOS::Kernel.state.fetch(:scheduler)
        task = scheduler.reap(pid)
        @output.puts(task ? "reaped #{pid} (#{task.state})" : "task #{pid} is not complete")
      when "debug"
        @output.puts RubyOS::Debug.snapshot.inspect
      when "sysinfo"
        cpus = RubyOS::Concurrency.stats
        scheduler = RubyOS::Kernel.state&.fetch(:scheduler, nil)
        @output.puts "RubyOS #{RubyOS::VERSION} (#{RUBY_DESCRIPTION})"
        @output.puts "CPUs: #{cpus.online}/#{cpus.cpus} online"
        @output.puts "Scheduler tasks: #{scheduler&.tasks&.length || 0}"
        @output.puts "Working directory: #{cwd}"
      when "netstat"
        @output.puts "lo     127.0.0.1"
        if @network
          @output.puts "eth0   #{@network.address}  gateway #{@network.gateway}"
        else
          @output.puts "eth0   unavailable (network not booted in this session)"
        end
      when "uptime"
        @output.puts "#{clock.milliseconds} ms"
      when "time"
        set_time(arguments.first) unless arguments.empty?
        @output.puts clock.format_hms
      when "sleep"
        duration = Integer(arguments.fetch(0))
        clock.sleep(duration)
        @output.puts "slept #{duration} ms"
      when "pwd"
        @output.puts cwd
      when "cd"
        destination = resolve_path(arguments.first || "/home")
        raise FS::NotDirectory, destination unless filesystem.stat(destination).type == :directory
        @cwd = destination
        @output.puts cwd
      when "ls"
        path = resolve_path(arguments.first || cwd)
        @output.puts filesystem.readdir(path).reject { |entry| [".", ".."].include?(entry) }.join("  ")
      when "cat"
        arguments.join(" ").split.each { |path| @output.write(filesystem.read_file(resolve_path(path))) }
      when "cp"
        source, destination = two_paths(arguments)
        bytes = filesystem.read_file(resolve_path(source))
        filesystem.write_file(resolve_path(destination), bytes)
        @output.puts "copied #{bytes.bytesize} bytes"
      when "mv"
        source, destination = two_paths(arguments)
        source = resolve_path(source)
        bytes = filesystem.read_file(source)
        filesystem.write_file(resolve_path(destination), bytes)
        filesystem.unlink(source)
        @output.puts "moved #{bytes.bytesize} bytes"
      when "write"
        path = resolve_path(arguments.fetch(0))
        filesystem.write_file(path, arguments.fetch(1, ""))
        @output.puts "#{arguments.fetch(1, "").bytesize} bytes"
      when "mkdir"
        path = resolve_path(arguments.fetch(0))
        filesystem.mkdir(path)
        @output.puts "created #{path}"
      when "rm"
        path = resolve_path(arguments.fetch(0))
        filesystem.unlink(path)
        @output.puts "removed #{path}"
      when "truncate"
        path = resolve_path(arguments.fetch(0))
        filesystem.truncate(path, Integer(arguments.fetch(1)))
        @output.puts "truncated #{path} to #{arguments.fetch(1)} bytes"
      when "run"
        path = resolve_path(arguments.fetch(0))
        result = eval(filesystem.read_file(path), @context, path, 1)
        @output.puts "=> #{result.inspect}"
      when "desktop"
        if arguments.empty?
          Apps::Catalog.build(kernel: RubyOS::Kernel).entries.each do |entry|
            @output.puts format("%-5s %s", entry.category, entry.name)
          end
        else
          launch_desktop(arguments.join(" "))
        end
      when "ed"
        launch_desktop("Editor", resolve_path(arguments.first || "/home/welcome.txt"))
      when "ftp"
        transfer_file(arguments)
      end
    rescue StandardError, SyntaxError => error
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

    def normalize_path(path)
      parts = []
      String(path).split("/").each do |part|
        next if part.empty? || part == "."
        part == ".." ? parts.pop : parts << part
      end
      "/" + parts.join("/")
    end

    def completion_receiver(name)
      symbol = String(name).to_sym
      return @context.local_variable_get(symbol) if @context.local_variable_defined?(symbol)
      return Object.const_get(name, false) if /\A[A-Z]\w*\z/.match?(name) && Object.const_defined?(name, false)
    rescue NameError
      nil
    end

    def path_candidates(token)
      slash = token.rindex("/")
      typed_directory = slash ? token[0..slash] : ""
      basename = slash ? token[(slash + 1)..] : token
      directory = typed_directory.empty? ? cwd : resolve_path(typed_directory)
      filesystem.readdir(directory).reject { |entry| [".", ".."].include?(entry) }
                .grep(/\A#{Regexp.escape(basename)}/).map do |entry|
        suffix = filesystem.stat(resolve_path("#{typed_directory}#{entry}")).type == :directory ? "/" : ""
        "#{typed_directory}#{entry}#{suffix}"
      end
    rescue FS::Error
      []
    end

    def resolve_path(path)
      value = String(path)
      normalize_path(value.start_with?("/") ? value : "#{cwd}/#{value}")
    end

    def two_paths(arguments)
      values = arguments.join(" ").split
      [values.fetch(0), values.fetch(1)]
    end

    def launch_desktop(name, *arguments)
      raise RubyOS::Error, "desktop is unavailable; start make run-gui" unless @desktop

      @desktop.call(String(name), *arguments)
      @output.puts "launched #{name}"
    end

    def transfer_file(arguments)
      raise RubyOS::Error, "network is unavailable in this session" unless @network

      values = arguments.join(" ").split
      operation = values.fetch(0)
      case operation
      when "get", "recv"
        destination = resolve_path(values.fetch(1))
        port = Integer(values.fetch(2, "7000"))
        connection = @network.listen(port).accept(timeout_ms: 30_000)
        bytes = +"".b
        loop do
          chunk = connection.read(timeout_ms: 30_000)
          break if chunk.empty?
          bytes << chunk
        end
        filesystem.write_file(destination, bytes)
        @output.puts "received #{bytes.bytesize} bytes into #{destination}"
        connection.close
      when "put", "send"
        source = resolve_path(values.fetch(1))
        host = values.fetch(2, @network.gateway.to_s)
        port = Integer(values.fetch(3, "7001"))
        connection = @network.connect(host, port, timeout_ms: 30_000)
        bytes = filesystem.read_file(source)
        connection.write(bytes)
        @output.puts "sent #{bytes.bytesize} bytes from #{source} to #{host}:#{port}"
        connection.close
      else
        raise ArgumentError, "usage: ftp get DST [PORT] | ftp put SRC [HOST] [PORT]"
      end
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
