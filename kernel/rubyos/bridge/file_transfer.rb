# frozen_string_literal: true

module RubyOS
  module Bridge
    class FileTransfer
      CHUNK_SIZE = 32 * 1024
      DEFAULT_LIMIT = 16 * 1024 * 1024

      attr_reader :client, :vfs, :limit

      def initialize(client:, vfs:, limit: DEFAULT_LIMIT)
        @client = client
        @vfs = vfs
        @limit = Integer(limit)
        raise ArgumentError, "file transfer limit must be positive" unless @limit.positive?
      end

      def import_supported? = client.features.include?("file.drop")
      def export_supported? = client.features.include?("file.export")

      def import(token:, name:, size:, directory: "/home")
        require_feature!("file.drop")
        token = Integer(token)
        size = Integer(size)
        raise ArgumentError, "invalid host file token" unless token.positive?
        raise ArgumentError, "invalid host file size" if size.negative?
        raise RubyOS::Error, "host file exceeds #{limit} byte limit" if size > limit

        destination = unused_path(directory, safe_name(name))
        descriptor = vfs.open(
          destination,
          FS::OpenFlags::WRITE_ONLY | FS::OpenFlags::CREATE | FS::OpenFlags::TRUNCATE
        )
        offset = 0
        complete = false
        begin
          loop do
            raise RubyOS::Error, "host import did not terminate at the size limit" if offset == limit

            result = client.call("host.file.read", {
              token:, offset:, length: [CHUNK_SIZE, limit - offset].min
            })
            hex = String(result.fetch("data", ""))
            unless hex.match?(/\A(?:[0-9a-fA-F]{2})*\z/)
              raise RubyOS::Error, "host returned malformed file data"
            end
            chunk = [hex].pack("H*")
            unless Integer(result.fetch("bytes", chunk.bytesize)) == chunk.bytesize
              raise RubyOS::Error, "host returned an inconsistent file chunk"
            end
            raise RubyOS::Error, "host file exceeds #{limit} byte limit" if offset + chunk.bytesize > limit

            written = 0
            while written < chunk.bytesize
              count = vfs.write(descriptor, chunk.byteslice(written..))
              raise RubyOS::Error, "short VFS write during host import" unless count.positive?

              written += count
            end
            offset += chunk.bytesize
            break if result.fetch("eof", false)
            raise RubyOS::Error, "host import stopped before EOF" if chunk.empty?
          end
          raise RubyOS::Error, "host file changed during transfer" unless offset == size

          complete = true
          [destination, offset]
        ensure
          vfs.close(descriptor)
          unless complete
            begin
              vfs.unlink(destination)
            rescue FS::Error
              nil
            end
          end
        end
      end

      def export(path)
        require_feature!("file.export")
        path = String(path)
        stat = vfs.stat(path)
        raise FS::IsDirectory, path unless stat.type == :file
        raise RubyOS::Error, "guest file exceeds #{limit} byte limit" if stat.size > limit

        descriptor = vfs.open(path, FS::OpenFlags::READ_ONLY)
        started = nil
        token = nil
        total = 0
        complete = false
        begin
          started = client.call("host.export.begin", { name: safe_name(path) })
          token = Integer(started.fetch("token", 0))
          raise RubyOS::Error, "desktop did not create an export" unless token.positive?

          loop do
            chunk = vfs.read(descriptor, CHUNK_SIZE)
            break if chunk.empty?

            raise RubyOS::Error, "guest file changed during export" if total + chunk.bytesize > limit
            result = client.call("host.export.chunk", { token: }, payload: chunk)
            unless Integer(result.fetch("bytes", -1)) == chunk.bytesize
              raise RubyOS::Error, "short host write during export"
            end
            total += chunk.bytesize
          end
          raise RubyOS::Error, "guest file changed during export" unless total == stat.size

          finished = client.call("host.export.finish", { token: })
          complete = true
          [String(finished.fetch("path", started.fetch("path", safe_name(path)))), total]
        ensure
          vfs.close(descriptor)
          begin
            client.call("host.export.abort", { token: }) if token&.positive? && !complete
          rescue StandardError
            nil
          end
        end
      end

      def safe_name(value)
        name = String(value || "").tr("\\", "/").split("/").last.to_s
        name = name.each_char.select { |character| character >= " " && character != "/" }.join
        name = "dropped-file" if name.empty? || [".", ".."].include?(name)
        name.each_char.first(255).join
      end

      private

      def require_feature!(name)
        raise RubyOS::Error, "desktop service does not support #{name}" unless client.features.include?(name)
      end

      def unused_path(directory, name)
        directory = normalize(directory)
        stat = vfs.stat(directory)
        raise FS::NotDirectory, directory unless stat.type == :directory

        candidate = join(directory, name)
        return candidate unless exists?(candidate)

        1.upto(9_999) do |suffix|
          candidate = join(directory, "#{name}.#{suffix}")
          return candidate unless exists?(candidate)
        end
        raise RubyOS::Error, "could not choose a unique destination name"
      end

      def exists?(path)
        vfs.stat(path)
        true
      rescue FS::NotFound
        false
      end

      def normalize(path)
        parts = []
        String(path).split("/").each do |part|
          next if part.empty? || part == "."
          part == ".." ? parts.pop : parts << part
        end
        "/" + parts.join("/")
      end

      def join(directory, name) = directory == "/" ? "/#{name}" : "#{directory}/#{name}"
    end
  end
end
