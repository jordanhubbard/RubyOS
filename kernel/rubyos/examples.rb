# frozen_string_literal: true

module RubyOS
  # Executable Ruby lessons live in the kernel image and are also mounted as a
  # readable curriculum under /examples. Track and lesson metadata are ordinary
  # immutable Ruby values, so the shell, VFS, tests, and future GUI browsers all
  # consume one catalog rather than maintaining parallel lists.
  module Examples
    Track = Data.define(:name, :summary, :next_track)
    Lesson = Data.define(:track, :name, :summary, :source)

    TRACKS = [
      Track.new(name: "start_here", summary: "meet RubyOS and read a small Ruby algorithm",
                next_track: "language"),
      Track.new(name: "language", summary: "canonical modern Ruby idioms in kernel-shaped code",
                next_track: "concurrency"),
      Track.new(name: "concurrency", summary: "Fibers, cooperative tasks, and native worker boundaries",
                next_track: "storage"),
      Track.new(name: "storage", summary: "files, descriptors, metadata, and the Ruby VFS",
                next_track: "networking"),
      Track.new(name: "networking", summary: "typed packets and protocol round trips",
                next_track: "graphics"),
      Track.new(name: "graphics", summary: "revision-tracked bitmaps and object-backed pixels",
                next_track: "audio"),
      Track.new(name: "audio", summary: "waveform synthesis, mixing, and PCM boundaries",
                next_track: "web"),
      Track.new(name: "web", summary: "Rack-shaped composition with Ruby callables",
                next_track: "internals"),
      Track.new(name: "internals", summary: "drivers, topology, and bounded object graphs",
                next_track: "demos"),
      Track.new(name: "demos", summary: "interactive Ruby language and media demonstrations",
                next_track: "games"),
      Track.new(name: "games", summary: "complete tick-driven Ruby arcade programs",
                next_track: nil)
    ].each(&:freeze).freeze

    def self.lesson(track, name, summary, source)
      Lesson.new(track:, name:, summary:, source: source.freeze).freeze
    end
    private_class_method :lesson

    LESSONS = [
      lesson("start_here", "hello_kernel", "inspect the live Ruby, devices, and scheduler", <<~'RUBY'),
        # /examples/start_here/hello_kernel.rb
        # Purpose: meet the running Ruby VM and inspect RubyOS through public objects.
        snapshot = RubyOS::Debug.snapshot
        {
          ruby: snapshot.fetch(:ruby),
          rubyos: snapshot.fetch(:rubyos),
          tasks: snapshot.fetch(:scheduler).fetch(:tasks).map { |task| task.fetch(:name) },
          cpus: snapshot.fetch(:concurrency).fetch(:online)
        }
      RUBY
      lesson("start_here", "prime_enumerator", "find primes with a lazy Enumerator pipeline", <<~'RUBY'),
        # /examples/start_here/prime_enumerator.rb
        # Purpose: introduce blocks, lambdas, ranges, Enumerable, and lazy evaluation.
        prime = lambda do |candidate|
          candidate >= 2 && (2..Math.sqrt(candidate).floor).none? do |divisor|
            (candidate % divisor).zero?
          end
        end
        (2..Float::INFINITY).lazy.select(&prime).first(15)
      RUBY
      lesson("language", "enumerable_pipeline", "lazy Enumerable select/map/take pipeline", <<~'RUBY'),
        # /examples/language/enumerable_pipeline.rb
        (1..Float::INFINITY).lazy
          .select(&:odd?)
          .map { |number| number * number }
          .first(5)
      RUBY
      lesson("language", "pattern_matching", "destructure a kernel event with case/in", <<~'RUBY'),
        # /examples/language/pattern_matching.rb
        event = { kind: :device, payload: { name: "virtio-net", bound: true } }
        case event
        in kind: :device, payload: { name:, bound: true }
          "#{name} is ready"
        else
          "not ready"
        end
      RUBY
      lesson("language", "fiber_stream", "resume a stateful Fiber producer", <<~'RUBY'),
        # /examples/language/fiber_stream.rb
        producer = Fiber.new do
          value = 1
          loop do
            Fiber.yield(value)
            value *= 2
          end
        end
        6.times.map { producer.resume }
      RUBY
      lesson("language", "mixin_protocol", "compose behavior with a module and super", <<~'RUBY'),
        # /examples/language/mixin_protocol.rb
        trace = Module.new do
          def call(value) = [self.class.name || "anonymous", super]
        end
        worker = Class.new do
          prepend trace
          def call(value) = value * 2
        end
        worker.new.call(21)
      RUBY
      lesson("language", "method_objects", "pass bound methods as first-class callables", <<~'RUBY'),
        # /examples/language/method_objects.rb
        formatter = "rubyos".method(:upcase)
        [formatter.call, formatter.owner, formatter.name]
      RUBY
      lesson("language", "data_records", "immutable value semantics with Data", <<~'RUBY'),
        # /examples/language/data_records.rb
        point_class = Data.define(:x, :y)
        points = [point_class.new(x: 3, y: 4), point_class.new(x: 6, y: 8)]
        points.map { |point| Math.sqrt(point.x**2 + point.y**2) }
      RUBY
      lesson("concurrency", "fiber_mailbox", "cooperative producer/consumer tasks", <<~'RUBY'),
        # /examples/concurrency/fiber_mailbox.rb
        # A bounded Enumerable channel supplies backpressure between Fibers.
        scheduler = RubyOS::Scheduler.new
        mailbox = RubyOS::Async::Channel.new(scheduler:, capacity: 1)
        received = []
        scheduler.spawn("pipeline") do
          RubyOS::Async::TaskGroup.open(scheduler) do |group|
            group.async("producer") do
              3.times { |index| mailbox << "message-#{index + 1}" }
              mailbox.close
            end
            group.async("consumer") { mailbox.each { |message| received << message } }
          end
        end
        scheduler.run
        received
      RUBY
      lesson("concurrency", "structured_tasks", "scope Fiber tasks with events and semaphores", <<~'RUBY'),
        # /examples/concurrency/structured_tasks.rb
        scheduler = RubyOS::Scheduler.new
        start = RubyOS::Async::Event.new(scheduler:)
        gate = RubyOS::Async::Semaphore.new(scheduler:, limit: 1)
        trace = []
        scheduler.spawn("supervisor") do
          RubyOS::Async::TaskGroup.open(scheduler) do |group|
            2.times do |index|
              group.async("worker-#{index + 1}") do
                start.wait
                gate.synchronize do
                  trace << "worker-#{index + 1}"
                  scheduler.yield_now
                end
              end
            end
            group.async("starter") { start.set }
          end
        end
        scheduler.run
        trace
      RUBY
      lesson("concurrency", "native_workers", "inspect CPUs and cross the native worker boundary", <<~'RUBY'),
        # /examples/concurrency/native_workers.rb
        # CRuby remains GVL-safe; bounded C work may run on RubyOS AP mailboxes.
        stats = RubyOS::Concurrency.stats
        digest = if defined?(RubyOS::HAL) && RubyOS::HAL.respond_to?(:worker_hash)
                   RubyOS::Concurrency.native_hash(42, rounds: 100)
                 else
                   :hosted_fallback
                 end
        { cpus: stats.cpus, online: stats.online, digest: }
      RUBY
      lesson("storage", "vfs_round_trip", "create, seek, read, stat, and unlink a VFS file", <<~'RUBY'),
        # /examples/storage/vfs_round_trip.rb
        root = RubyOS::FS::TmpFS.new.seed("notes" => {})
        vfs = RubyOS::FS::VFS.new.mount("/", root)
        flags = RubyOS::FS::OpenFlags
        descriptor = vfs.open("/notes/ruby.txt", flags::CREATE | flags::READ_WRITE)
        vfs.write(descriptor, "objects persist bytes")
        vfs.seek(descriptor, 0)
        text = vfs.read(descriptor, 64)
        vfs.close(descriptor)
        size = vfs.stat("/notes/ruby.txt").size
        vfs.unlink("/notes/ruby.txt")
        { text:, size:, remaining: vfs.readdir("/notes") - [".", ".."] }
      RUBY
      lesson("networking", "packet_round_trip", "encode and decode typed IPv4 and UDP values", <<~'RUBY'),
        # /examples/networking/packet_round_trip.rb
        source = RubyOS::Net::IPv4Address.new("10.0.2.15")
        destination = RubyOS::Net::IPv4Address.new("10.0.2.2")
        udp = RubyOS::Net::UDPSegment.new(49_152, 7, "hello from Ruby")
        payload = udp.encode(source_ip: source, destination_ip: destination)
        packet = RubyOS::Net::IPv4Packet.new(
          source, destination, RubyOS::Net::IPv4Packet::UDP, payload, 64, 1, 0x4000
        )
        decoded = RubyOS::Net::IPv4Packet.decode(packet.encode)
        message = RubyOS::Net::UDPSegment.decode(decoded.payload)
        { from: decoded.source.to_s, to: decoded.destination.to_s, body: message.payload }
      RUBY
      lesson("graphics", "bitmap_gradient", "draw revision-tracked pixels with ranges", <<~'RUBY'),
        # /examples/graphics/bitmap_gradient.rb
        bitmap = RubyOS::Media::Bitmap.new(16, 8)
        (0...bitmap.height).each do |y|
          (0...bitmap.width).each do |x|
            bitmap.put(x, y, RubyOS::Media::Color.rgb(x * 16, y * 28, 180))
          end
        end
        { size: [bitmap.width, bitmap.height], colors: bitmap.raster.uniq.length,
          revision: bitmap.revision }
      RUBY
      lesson("audio", "chord_synthesis", "mix sine, square, and triangle PCM", <<~'RUBY'),
        # /examples/audio/chord_synthesis.rb
        mixer = RubyOS::Sound::Mixer.new
        chord = mixer.mix(
          RubyOS::Sound::Waveform.sine(220, duration_ms: 25, amplitude: 0.15),
          RubyOS::Sound::Waveform.square(330, duration_ms: 25, amplitude: 0.08),
          RubyOS::Sound::Waveform.triangle(440, duration_ms: 25, amplitude: 0.08)
        )
        { frames: chord.frames, bytes: chord.stereo_bytes.bytesize }
      RUBY
      lesson("web", "rack_router", "compose a Rack-shaped router from Ruby blocks", <<~'RUBY'),
        # /examples/web/rack_router.rb
        router = RubyOS::HTTP::Router.new
          .get("/") { "Ruby blocks are the router.\n" }
          .get("/healthz") { "ok\n" }
        status, headers, body = router.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/")
        { status:, content_type: headers.fetch("content-type"), body: body.join.strip }
      RUBY
      lesson("internals", "driver_binding", "match a typed device to a Ruby driver", <<~'RUBY'),
        # /examples/internals/driver_binding.rb
        bus = RubyOS::Bus.new
        console = bus.add(RubyOS::Device.new("lesson-console", kind: :serial, port: 0x3f8))
        bus.bind([RubyOS::SerialDriver])
        { topology: bus.topology, driver: console.driver.class.name }
      RUBY
      lesson("internals", "object_graph", "walk a bounded cycle-aware Ruby object graph", <<~'RUBY')
        # /examples/internals/object_graph.rb
        root = { language: "Ruby", children: [] }
        root.fetch(:children) << root
        graph = RubyOS::Introspection.object_graph(root, depth: 3, limit: 16)
        { objects: graph.fetch(:nodes).length, edges: graph.fetch(:edges).length }
      RUBY
    ].freeze

    module_function

    def each(track = nil, &block)
      lessons = track ? lessons_for(track) : LESSONS
      return lessons.each unless block

      lessons.each(&block)
    end

    def tracks = TRACKS

    def fetch_track(name)
      TRACKS.find { |track| track.name == String(name).delete_prefix("/").delete_suffix("/") } ||
        raise(KeyError, "unknown example track: #{name}")
    end

    def lessons_for(track)
      name = fetch_track(track).name
      LESSONS.select { |lesson| lesson.track == name }.freeze
    end

    def fetch(selector)
      value = String(selector).delete_prefix("/examples/").delete_suffix(".rb")
      track_name, lesson_name = value.include?("/") ? value.split("/", 2) : [nil, value]
      matches = LESSONS.select do |lesson|
        lesson.name == lesson_name && (!track_name || lesson.track == track_name)
      end
      return matches.first if matches.one?
      raise KeyError, "ambiguous example: #{selector}" if matches.length > 1

      raise KeyError, "unknown example: #{selector}"
    end

    def path_for(lesson)
      lesson = fetch(lesson) unless lesson.is_a?(Lesson)
      "/examples/#{lesson.track}/#{lesson.name}.rb"
    end

    def run(name, context: TOPLEVEL_BINDING)
      lesson = fetch(name)
      eval(lesson.source, context, path_for(lesson), 1)
    end

    def files
      TRACKS.to_h do |track|
        lessons = lessons_for(track.name)
        entries = lessons.to_h { |lesson| ["#{lesson.name}.rb", lesson.source] }
        [track.name, { "README.txt" => track_guide(track) }.merge(entries)]
      end.merge("README.txt" => root_guide)
    end

    def root_guide
      lines = [
        "RubyOS learning examples", "========================", "",
        "This tree is a curriculum built from executable, frozen Ruby source.",
        "Start with /examples/start_here, then follow the track guides.", "",
        "Suggested learning path", "-----------------------", ""
      ]
      %w[start_here language concurrency storage networking graphics audio web internals].each_with_index do |name, index|
        lesson = lessons_for(name).first
        lines << "  #{index + 1}. example #{lesson.track}/#{lesson.name}"
      end
      lines += ["", "Tracks", "------", ""]
      TRACKS.each { |track| lines << format("  %-13s %s", "#{track.name}/", track.summary) }
      lines += ["", "Discover with: examples [track]", "Run with:      example TRACK/NAME", "",
                "Use Files or Editor to read and change the mounted source."]
      lines.join("\n") + "\n"
    end

    def track_guide(track)
      lessons = lessons_for(track.name)
      title = track.name.tr("_", " ").split.map(&:capitalize).join(" ")
      lines = [title, "=" * title.length, "", track.summary, ""]
      if lessons.empty?
        lines << "This track lives in the graphical Apps catalog. Run `apps` to browse it."
      else
        lessons.each_with_index do |lesson, index|
          lines << "#{index + 1}. #{lesson.name}.rb"
          lines << "   #{lesson.summary}"
          lines << ""
          lines << "     example #{lesson.track}/#{lesson.name}"
          lines << ""
        end
      end
      lines << "Next: /examples/#{track.next_track}/README.txt" if track.next_track
      lines.join("\n") + "\n"
    end
  end
end
