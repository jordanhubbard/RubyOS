# frozen_string_literal: true

module RubyOS
  module FS
    class Error < RubyOS::Error; end
    class NotFound < Error; end
    class Exists < Error; end
    class NotDirectory < Error; end
    class IsDirectory < Error; end
    class BadDescriptor < Error; end
    class PermissionDenied < Error; end

    Stat = Data.define(:type, :size, :mode, :links)

    module OpenFlags
      READ_ONLY = 0
      WRITE_ONLY = 1
      READ_WRITE = 2
      CREATE = 0x040
      TRUNCATE = 0x200
      APPEND = 0x400
    end

    class TmpfsNode
      attr_reader :type, :mode, :children

      def initialize(type, mode: nil)
        @type = type
        @mode = mode || (directory? ? 0o755 : 0o644)
        @data = +"".b
        @children = {}
      end

      def directory?
        type == :directory
      end

      def file?
        type == :file
      end

      def stat
        Stat.new(type:, size: @data.bytesize, mode:,
                 links: directory? ? 1 + children.size : 1)
      end

      def read(offset, length)
        raise IsDirectory, "cannot read a directory" unless file?
        @data.byteslice(offset, length) || +"".b
      end

      def write(offset, bytes)
        raise IsDirectory, "cannot write a directory" unless file?
        bytes = String(bytes).b
        @data << "\0" * (offset - @data.bytesize) if offset > @data.bytesize
        required = offset + bytes.bytesize
        @data << "\0" * (required - @data.bytesize) if required > @data.bytesize
        @data[offset, bytes.bytesize] = bytes
        bytes.bytesize
      end

      def truncate(size = 0)
        raise IsDirectory, "cannot truncate a directory" unless file?
        if size <= @data.bytesize
          @data = @data.byteslice(0, size)
        else
          @data << "\0" * (size - @data.bytesize)
        end
        self
      end

      def entries
        raise NotDirectory, "not a directory" unless directory?
        [".", "..", *children.keys]
      end

      def lookup(name)
        return self if name == "." || name.empty?
        raise NotDirectory, "not a directory" unless directory?
        children.fetch(name) { raise NotFound, name }
      end

      def create(name, type)
        raise NotDirectory, "not a directory" unless directory?
        raise Exists, name if children.key?(name)
        children[name] = TmpfsNode.new(type)
      end

      def unlink(name)
        node = children.fetch(name) { raise NotFound, name }
        raise Error, "directory not empty" if node.directory? && !node.children.empty?
        children.delete(name)
      end
    end

    class TmpFS
      attr_reader :root

      def initialize
        @root = TmpfsNode.new(:directory)
      end

      def seed(tree)
        seed_node(root, tree)
        self
      end

      private

      def seed_node(parent, tree)
        tree.each do |name, value|
          if value.is_a?(Hash)
            seed_node(parent.create(String(name), :directory), value)
          else
            parent.create(String(name), :file).write(0, String(value))
          end
        end
      end
    end

    class NodeFS
      attr_reader :root

      def initialize(root)
        @root = root
      end
    end

    class VFS
      Handle = Data.define(:node, :flags, :offset)

      def initialize
        @mounts = {}
        @handles = {}
        @next_descriptor = 3
      end

      def mount(path, filesystem)
        @mounts[normalize(path)] = filesystem
        self
      end

      def unmount(path)
        @mounts.delete(normalize(path)) { raise NotFound, path }
      end

      def open(path, flags = OpenFlags::READ_ONLY)
        node = resolve(path, create: (flags & OpenFlags::CREATE) != 0)
        node.truncate if (flags & OpenFlags::TRUNCATE) != 0
        offset = (flags & OpenFlags::APPEND) != 0 ? node.stat.size : 0
        descriptor = @next_descriptor
        @next_descriptor += 1
        @handles[descriptor] = Handle.new(node:, flags:, offset:)
        descriptor
      end

      def close(descriptor)
        @handles.delete(descriptor) { raise BadDescriptor, descriptor.to_s }
        nil
      end

      def read(descriptor, length)
        handle = fetch(descriptor)
        access = handle.flags & 0x3
        raise PermissionDenied, "descriptor is write-only" if access == OpenFlags::WRITE_ONLY
        bytes = handle.node.read(handle.offset, length)
        replace_handle(descriptor, handle, handle.offset + bytes.bytesize)
        bytes
      end

      def write(descriptor, bytes)
        handle = fetch(descriptor)
        access = handle.flags & 0x3
        raise PermissionDenied, "descriptor is read-only" if access == OpenFlags::READ_ONLY
        count = handle.node.write(handle.offset, bytes)
        replace_handle(descriptor, handle, handle.offset + count)
        count
      end

      def seek(descriptor, offset, whence = :set)
        handle = fetch(descriptor)
        position = case whence
                   when :set then offset
                   when :current then handle.offset + offset
                   when :end then handle.node.stat.size + offset
                   else raise ArgumentError, "unknown seek origin"
                   end
        raise ArgumentError, "negative file position" if position.negative?
        replace_handle(descriptor, handle, position)
        position
      end

      def stat(path)
        resolve(path).stat
      end

      def readdir(path)
        entries = resolve(path).entries
        mount_children(path).each { |name| entries << name unless entries.include?(name) }
        entries
      end

      def mkdir(path)
        parent, name = resolve_parent(path)
        parent.create(name, :directory)
      end

      def unlink(path)
        parent, name = resolve_parent(path)
        parent.unlink(name)
      end

      def read_file(path)
        node = resolve(path)
        node.read(0, node.stat.size)
      end

      def write_file(path, bytes)
        descriptor = open(path, OpenFlags::WRITE_ONLY | OpenFlags::CREATE | OpenFlags::TRUNCATE)
        write(descriptor, bytes)
      ensure
        close(descriptor) if descriptor
      end

      private

      def normalize(path)
        parts = []
        String(path).split("/").each do |part|
          next if part.empty? || part == "."
          part == ".." ? parts.pop : parts << part
        end
        "/" + parts.join("/")
      end

      def route(path)
        absolute = normalize(path)
        mount = @mounts.keys.select do |candidate|
          candidate == "/" || absolute == candidate || absolute.start_with?(candidate + "/")
        end.max_by(&:bytesize)
        raise NotFound, "no filesystem mounted for #{absolute}" unless mount
        relative = absolute.delete_prefix(mount)
        [@mounts.fetch(mount), relative.empty? ? "/" : relative]
      end

      def resolve(path, create: false)
        filesystem, relative = route(path)
        parts = relative.split("/").reject(&:empty?)
        node = filesystem.root
        parts.each_with_index do |part, index|
          begin
            node = node.lookup(part)
          rescue NotFound
            raise unless create && index == parts.length - 1
            node = node.create(part, :file)
          end
        end
        node
      end

      def resolve_parent(path)
        absolute = normalize(path)
        parts = absolute.split("/").reject(&:empty?)
        raise Error, "cannot modify root" if parts.empty?
        name = parts.pop
        [resolve("/" + parts.join("/")), name]
      end

      def mount_children(path)
        parent = normalize(path)
        prefix = parent == "/" ? "/" : parent + "/"
        @mounts.keys.filter_map do |mount|
          next unless mount.start_with?(prefix)
          tail = mount.delete_prefix(prefix)
          tail unless tail.empty? || tail.include?("/")
        end
      end

      def fetch(descriptor)
        @handles.fetch(descriptor) { raise BadDescriptor, descriptor.to_s }
      end

      def replace_handle(descriptor, handle, offset)
        @handles[descriptor] = Handle.new(node: handle.node, flags: handle.flags, offset:)
      end
    end
  end
end
