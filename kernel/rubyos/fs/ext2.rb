# frozen_string_literal: true

module RubyOS
  module FS
    class Ext2
      MAGIC = 0xef53
      ROOT_INODE = 2
      DIRECTORY_MODE = 0x4000
      REGULAR_MODE = 0x8000
      SYMLINK_MODE = 0xa000
      TYPE_MASK = 0xf000
      DIRECT_BLOCKS = 12

      class FileBlockDevice
        attr_reader :size

        def initialize(path)
          @file = File.open(path, "rb")
          @size = @file.stat.size
        end

        def read(offset, length)
          raise RangeError, "block read outside device" if offset.negative? || offset + length > size
          @file.seek(offset)
          @file.read(length)
        end

        def close
          @file.close
        end
      end

      attr_reader :root, :block_size

      def initialize(device)
        @device = device
        superblock = device.read(1024, 1024)
        raise Error, "short ext2 superblock" unless superblock&.bytesize == 1024
        raise Error, "bad ext2 magic" unless u16(superblock, 56) == MAGIC

        @blocks_count = u32(superblock, 4)
        @first_data_block = u32(superblock, 20)
        @block_size = 1024 << u32(superblock, 24)
        @blocks_per_group = u32(superblock, 32)
        @inodes_per_group = u32(superblock, 40)
        revision = u32(superblock, 76)
        @inode_size = revision >= 1 ? u16(superblock, 88) : 128
        incompat = revision >= 1 ? u32(superblock, 96) : 0
        raise Error, format("unsupported ext2 incompat features %#x", incompat) unless (incompat & ~0x2).zero?
        raise Error, "invalid ext2 block size" unless @block_size >= 1024 && (@block_size % 512).zero?

        group_count = (@blocks_count - @first_data_block + @blocks_per_group - 1) / @blocks_per_group
        table_block = @block_size == 1024 ? 2 : 1
        @group_descriptors = device.read(table_block * @block_size, group_count * 32)
        @root = Node.new(self, ROOT_INODE)
      end

      def inode(number)
        zero_based = number - 1
        group = zero_based / @inodes_per_group
        local = zero_based % @inodes_per_group
        inode_table = u32(@group_descriptors, group * 32 + 8)
        offset = inode_table * @block_size + local * @inode_size
        raw = @device.read(offset, @inode_size)
        raise NotFound, "inode #{number}" unless raw&.bytesize == @inode_size
        raw
      end

      def mode(raw)
        u16(raw, 0)
      end

      def size(raw)
        low = u32(raw, 4)
        return low unless (mode(raw) & TYPE_MASK) == REGULAR_MODE
        low | (u32(raw, 108) << 32)
      end

      def links(raw)
        u16(raw, 26)
      end

      def read_inode(number, offset, length)
        raw = inode(number)
        file_size = size(raw)
        return +"".b if offset >= file_size
        remaining = [length, file_size - offset].min
        output = +"".b
        cursor = offset
        while remaining.positive?
          logical = cursor / @block_size
          within = cursor % @block_size
          count = [remaining, @block_size - within].min
          physical = data_block(raw, logical)
          output << if physical.zero?
                      "\0" * count
                    else
                      @device.read(physical * @block_size + within, count)
                    end
          cursor += count
          remaining -= count
        end
        output
      end

      def entries(number)
        raw = inode(number)
        raise NotDirectory, number.to_s unless (mode(raw) & TYPE_MASK) == DIRECTORY_MODE
        data = read_inode(number, 0, size(raw))
        entries = []
        offset = 0
        while offset + 8 <= data.bytesize
          inode_number = u32(data, offset)
          record_length = u16(data, offset + 4)
          name_length = data.getbyte(offset + 6)
          raise Error, "invalid ext2 directory record" if record_length < 8 || offset + record_length > data.bytesize
          if inode_number != 0 && name_length <= record_length - 8
            name = data.byteslice(offset + 8, name_length)
            entries << [name, inode_number]
          end
          offset += record_length
        end
        entries
      end

      private

      def data_block(raw, logical)
        return u32(raw, 40 + logical * 4) if logical < DIRECT_BLOCKS

        pointers_per_block = @block_size / 4
        logical -= DIRECT_BLOCKS
        if logical < pointers_per_block
          indirect = u32(raw, 40 + DIRECT_BLOCKS * 4)
          return 0 if indirect.zero?
          return u32(read_block(indirect), logical * 4)
        end

        logical -= pointers_per_block
        raise Error, "triple-indirect ext2 blocks are not supported" if logical >= pointers_per_block**2
        double_indirect = u32(raw, 40 + (DIRECT_BLOCKS + 1) * 4)
        return 0 if double_indirect.zero?
        first = u32(read_block(double_indirect), logical / pointers_per_block * 4)
        return 0 if first.zero?
        u32(read_block(first), logical % pointers_per_block * 4)
      end

      def read_block(number)
        @device.read(number * @block_size, @block_size)
      end

      def u16(bytes, offset)
        bytes.byteslice(offset, 2).unpack1("S<")
      end

      def u32(bytes, offset)
        bytes.byteslice(offset, 4).unpack1("L<")
      end

      class Node
        def initialize(filesystem, inode_number)
          @filesystem = filesystem
          @inode_number = inode_number
        end

        def stat
          raw = @filesystem.inode(@inode_number)
          mode = @filesystem.mode(raw)
          type = case mode & TYPE_MASK
                 when DIRECTORY_MODE then :directory
                 when SYMLINK_MODE then :symlink
                 else :file
                 end
          Stat.new(type:, size: @filesystem.size(raw), mode: mode & 0o7777,
                   links: @filesystem.links(raw))
        end

        def read(offset, length)
          raise IsDirectory, @inode_number.to_s if stat.type == :directory
          @filesystem.read_inode(@inode_number, offset, length)
        end

        def entries
          [".", "..", *@filesystem.entries(@inode_number).map(&:first).reject { |name| name == "." || name == ".." }]
        end

        def lookup(name)
          return self if name == "." || name.empty?
          pair = @filesystem.entries(@inode_number).find { |entry_name, _| entry_name == name }
          raise NotFound, name unless pair
          self.class.new(@filesystem, pair.last)
        end

        def write(*)
          raise PermissionDenied, "ext2 milestone is read-only"
        end

        def truncate(*)
          raise PermissionDenied, "ext2 milestone is read-only"
        end

        def create(*)
          raise PermissionDenied, "ext2 milestone is read-only"
        end

        def unlink(*)
          raise PermissionDenied, "ext2 milestone is read-only"
        end
      end
    end
  end
end
