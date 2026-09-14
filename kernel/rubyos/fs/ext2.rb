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

        def initialize(path, readonly: false)
          @file = File.open(path, readonly ? "rb" : "r+b")
          @size = @file.stat.size
          @readonly = readonly
        end

        def read(offset, length)
          raise RangeError, "block read outside device" if offset.negative? || offset + length > size
          @file.seek(offset)
          @file.read(length)
        end

        def write(offset, bytes)
          raise PermissionDenied, "block device is read-only" if @readonly
          bytes = String(bytes).b
          raise RangeError, "block write outside device" if offset.negative? || offset + bytes.bytesize > size
          @file.seek(offset)
          @file.write(bytes)
          @file.flush
          bytes.bytesize
        end

        def close
          @file.close
        end
      end

      attr_reader :root, :block_size

      def initialize(device)
        @device = device
        @superblock = device.read(1024, 1024)
        raise Error, "short ext2 superblock" unless @superblock&.bytesize == 1024
        raise Error, "bad ext2 magic" unless u16(@superblock, 56) == MAGIC

        @blocks_count = u32(@superblock, 4)
        @first_data_block = u32(@superblock, 20)
        @block_size = 1024 << u32(@superblock, 24)
        @blocks_per_group = u32(@superblock, 32)
        @inodes_per_group = u32(@superblock, 40)
        revision = u32(@superblock, 76)
        @inode_size = revision >= 1 ? u16(@superblock, 88) : 128
        incompat = revision >= 1 ? u32(@superblock, 96) : 0
        raise Error, format("unsupported ext2 incompat features %#x", incompat) unless (incompat & ~0x2).zero?
        raise Error, "invalid ext2 block size" unless @block_size >= 1024 && (@block_size % 512).zero?

        group_count = (@blocks_count - @first_data_block + @blocks_per_group - 1) / @blocks_per_group
        table_block = @block_size == 1024 ? 2 : 1
        @group_table_offset = table_block * @block_size
        @group_count = group_count
        @group_descriptors = device.read(@group_table_offset, group_count * 32)
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

      def write_inode(number, offset, bytes)
        bytes = String(bytes).b
        raw = inode(number)
        raise IsDirectory, number.to_s unless (mode(raw) & TYPE_MASK) == REGULAR_MODE
        cursor = offset
        source_offset = 0
        while source_offset < bytes.bytesize
          logical = cursor / @block_size
          within = cursor % @block_size
          count = [bytes.bytesize - source_offset, @block_size - within].min
          physical = allocate_data_block(raw, logical)
          block = read_block(physical).dup
          block[within, count] = bytes.byteslice(source_offset, count)
          write_block(physical, block)
          cursor += count
          source_offset += count
        end
        set_u64_size(raw, [size(raw), offset + bytes.bytesize].max)
        persist_inode(number, raw)
        bytes.bytesize
      end

      def truncate_inode(number, new_size = 0)
        raw = inode(number)
        raise IsDirectory, number.to_s unless (mode(raw) & TYPE_MASK) == REGULAR_MODE
        raise Error, "nonzero ext2 truncate is not implemented" unless new_size.zero?
        free_inode_blocks(raw)
        set_u64_size(raw, 0)
        persist_inode(number, raw)
      end

      def create_child(parent_number, name, type)
        name = String(name).b
        raise Error, "invalid ext2 name" if name.empty? || name.bytesize > 255 || name.include?("/")
        raise Exists, name if entries(parent_number).any? { |entry_name, _| entry_name == name }
        directory = type == :directory
        number = allocate_inode(directory:)
        raw = "\0".b * @inode_size
        set_u16(raw, 0, (directory ? DIRECTORY_MODE | 0o755 : REGULAR_MODE | 0o644))
        set_u16(raw, 26, directory ? 2 : 1)

        if directory
          physical = allocate_block
          set_u32(raw, 40, physical)
          set_u32(raw, 28, @block_size / 512)
          set_u64_size(raw, @block_size)
          dot = [number, 12, 1, 2].pack("L<S<CC") + ".\0\0\0"
          dotdot = [parent_number, @block_size - 12, 2, 2].pack("L<S<CC") + ".."
          write_block(physical, (dot + dotdot).ljust(@block_size, "\0"))
          parent = inode(parent_number)
          set_u16(parent, 26, u16(parent, 26) + 1)
          persist_inode(parent_number, parent)
        end

        persist_inode(number, raw)
        add_directory_entry(parent_number, name, number, directory ? 2 : 1)
        Node.new(self, number)
      end

      def unlink_child(parent_number, name)
        name = String(name).b
        raise PermissionDenied, "cannot unlink dot entries" if name == "." || name == ".."
        pair = entries(parent_number).find { |entry_name, _| entry_name == name }
        raise NotFound, name unless pair
        number = pair.last
        raw = inode(number)
        directory = (mode(raw) & TYPE_MASK) == DIRECTORY_MODE
        if directory
          children = entries(number).reject { |entry_name, _| entry_name == "." || entry_name == ".." }
          raise Error, "directory not empty" unless children.empty?
        end

        remove_directory_entry(parent_number, name)
        parent = inode(parent_number)
        if directory
          set_u16(parent, 26, u16(parent, 26) - 1)
          persist_inode(parent_number, parent)
          set_u16(raw, 26, 0)
        else
          set_u16(raw, 26, [u16(raw, 26) - 1, 0].max)
        end

        if u16(raw, 26).zero?
          free_inode_blocks(raw)
          persist_inode(number, "\0".b * @inode_size)
          free_inode(number, directory:)
        else
          persist_inode(number, raw)
        end
        nil
      end

      private

      def allocate_data_block(raw, logical)
        if logical < DIRECT_BLOCKS
          physical = u32(raw, 40 + logical * 4)
          if physical.zero?
            physical = allocate_block
            write_block(physical, "\0".b * @block_size)
            set_u32(raw, 40 + logical * 4, physical)
            set_u32(raw, 28, u32(raw, 28) + @block_size / 512)
          end
          return physical
        end

        logical -= DIRECT_BLOCKS
        pointers_per_block = @block_size / 4
        raise Error, "ext2 writes beyond single-indirect blocks are not implemented" if logical >= pointers_per_block
        indirect = u32(raw, 40 + DIRECT_BLOCKS * 4)
        if indirect.zero?
          indirect = allocate_block
          write_block(indirect, "\0".b * @block_size)
          set_u32(raw, 40 + DIRECT_BLOCKS * 4, indirect)
          set_u32(raw, 28, u32(raw, 28) + @block_size / 512)
        end
        pointers = read_block(indirect).dup
        physical = u32(pointers, logical * 4)
        if physical.zero?
          physical = allocate_block
          write_block(physical, "\0".b * @block_size)
          set_u32(pointers, logical * 4, physical)
          write_block(indirect, pointers)
          set_u32(raw, 28, u32(raw, 28) + @block_size / 512)
        end
        physical
      end

      def allocate_block
        @group_count.times do |group|
          descriptor = group * 32
          free = u16(@group_descriptors, descriptor + 12)
          next if free.zero?
          bitmap_number = u32(@group_descriptors, descriptor)
          count = [@blocks_per_group,
                   @blocks_count - (@first_data_block + group * @blocks_per_group)].min
          index = allocate_bitmap_bit(bitmap_number, count)
          set_u16(@group_descriptors, descriptor + 12, free - 1)
          set_u32(@superblock, 12, u32(@superblock, 12) - 1)
          flush_metadata
          return @first_data_block + group * @blocks_per_group + index
        end
        raise Error, "ext2 has no free blocks"
      end

      def allocate_inode(directory:)
        @group_count.times do |group|
          descriptor = group * 32
          free = u16(@group_descriptors, descriptor + 14)
          next if free.zero?
          bitmap_number = u32(@group_descriptors, descriptor + 4)
          index = allocate_bitmap_bit(bitmap_number, @inodes_per_group)
          set_u16(@group_descriptors, descriptor + 14, free - 1)
          set_u32(@superblock, 16, u32(@superblock, 16) - 1)
          if directory
            set_u16(@group_descriptors, descriptor + 16,
                    u16(@group_descriptors, descriptor + 16) + 1)
          end
          flush_metadata
          return group * @inodes_per_group + index + 1
        end
        raise Error, "ext2 has no free inodes"
      end

      def allocate_bitmap_bit(block_number, count)
        bitmap = read_block(block_number).dup
        count.times do |index|
          byte_index = index / 8
          mask = 1 << (index % 8)
          next unless (bitmap.getbyte(byte_index) & mask).zero?
          bitmap.setbyte(byte_index, bitmap.getbyte(byte_index) | mask)
          write_block(block_number, bitmap)
          return index
        end
        raise Error, "ext2 bitmap is full"
      end

      def add_directory_entry(parent_number, name, child_number, file_type)
        raw = inode(parent_number)
        raise NotDirectory, parent_number.to_s unless (mode(raw) & TYPE_MASK) == DIRECTORY_MODE
        required = (8 + name.bytesize + 3) & ~3
        blocks = (size(raw) + @block_size - 1) / @block_size
        blocks.times do |logical|
          physical = data_block(raw, logical)
          next if physical.zero?
          block = read_block(physical).dup
          offset = 0
          while offset + 8 <= @block_size
            record_length = u16(block, offset + 4)
            break if record_length < 8
            actual = (8 + block.getbyte(offset + 6) + 3) & ~3
            if record_length - actual >= required
              set_u16(block, offset + 4, actual)
              insert = offset + actual
              block[insert, 8] = [child_number, record_length - actual,
                                  name.bytesize, file_type].pack("L<S<CC")
              block[insert + 8, name.bytesize] = name
              write_block(physical, block)
              return
            end
            offset += record_length
          end
        end

        physical = allocate_data_block(raw, blocks)
        block = "\0".b * @block_size
        block[0, 8] = [child_number, @block_size, name.bytesize, file_type].pack("L<S<CC")
        block[8, name.bytesize] = name
        write_block(physical, block)
        set_u64_size(raw, (blocks + 1) * @block_size)
        persist_inode(parent_number, raw)
      end

      def remove_directory_entry(parent_number, name)
        raw = inode(parent_number)
        blocks = (size(raw) + @block_size - 1) / @block_size
        blocks.times do |logical|
          physical = data_block(raw, logical)
          next if physical.zero?
          block = read_block(physical).dup
          offset = 0
          previous = nil
          while offset + 8 <= @block_size
            number = u32(block, offset)
            record_length = u16(block, offset + 4)
            break if record_length < 8 || offset + record_length > @block_size
            length = block.getbyte(offset + 6)
            entry_name = block.byteslice(offset + 8, length)
            if number != 0 && entry_name == name
              if previous
                set_u16(block, previous + 4, u16(block, previous + 4) + record_length)
              else
                set_u32(block, offset, 0)
              end
              write_block(physical, block)
              return
            end
            previous = offset if number != 0
            offset += record_length
          end
        end
        raise NotFound, name
      end

      def free_inode_blocks(raw)
        DIRECT_BLOCKS.times do |index|
          physical = u32(raw, 40 + index * 4)
          free_block(physical) unless physical.zero?
          set_u32(raw, 40 + index * 4, 0)
        end
        indirect = u32(raw, 40 + DIRECT_BLOCKS * 4)
        unless indirect.zero?
          pointers = read_block(indirect)
          (@block_size / 4).times do |index|
            physical = u32(pointers, index * 4)
            free_block(physical) unless physical.zero?
          end
          free_block(indirect)
          set_u32(raw, 40 + DIRECT_BLOCKS * 4, 0)
        end
        set_u32(raw, 28, 0)
      end

      def free_block(number)
        relative = number - @first_data_block
        group = relative / @blocks_per_group
        index = relative % @blocks_per_group
        descriptor = group * 32
        bitmap_number = u32(@group_descriptors, descriptor)
        bitmap = read_block(bitmap_number).dup
        byte_index = index / 8
        mask = 1 << (index % 8)
        bitmap.setbyte(byte_index, bitmap.getbyte(byte_index) & ~mask)
        write_block(bitmap_number, bitmap)
        set_u16(@group_descriptors, descriptor + 12,
                u16(@group_descriptors, descriptor + 12) + 1)
        set_u32(@superblock, 12, u32(@superblock, 12) + 1)
        flush_metadata
      end

      def free_inode(number, directory:)
        zero_based = number - 1
        group = zero_based / @inodes_per_group
        index = zero_based % @inodes_per_group
        descriptor = group * 32
        bitmap_number = u32(@group_descriptors, descriptor + 4)
        bitmap = read_block(bitmap_number).dup
        byte_index = index / 8
        mask = 1 << (index % 8)
        raise Error, "ext2 inode #{number} already free" if (bitmap.getbyte(byte_index) & mask).zero?
        bitmap.setbyte(byte_index, bitmap.getbyte(byte_index) & ~mask)
        write_block(bitmap_number, bitmap)
        set_u16(@group_descriptors, descriptor + 14,
                u16(@group_descriptors, descriptor + 14) + 1)
        set_u32(@superblock, 16, u32(@superblock, 16) + 1)
        if directory
          set_u16(@group_descriptors, descriptor + 16,
                  u16(@group_descriptors, descriptor + 16) - 1)
        end
        flush_metadata
      end

      def persist_inode(number, raw)
        zero_based = number - 1
        group = zero_based / @inodes_per_group
        local = zero_based % @inodes_per_group
        inode_table = u32(@group_descriptors, group * 32 + 8)
        @device.write(inode_table * @block_size + local * @inode_size, raw)
      end

      def write_block(number, bytes)
        raise ArgumentError, "ext2 block size mismatch" unless bytes.bytesize == @block_size
        @device.write(number * @block_size, bytes)
      end

      def flush_metadata
        @device.write(1024, @superblock)
        @device.write(@group_table_offset, @group_descriptors)
      end

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

      def set_u16(bytes, offset, value)
        bytes[offset, 2] = [value].pack("S<")
      end

      def set_u32(bytes, offset, value)
        bytes[offset, 4] = [value].pack("L<")
      end

      def set_u64_size(raw, value)
        set_u32(raw, 4, value & 0xffffffff)
        set_u32(raw, 108, value >> 32) if (mode(raw) & TYPE_MASK) == REGULAR_MODE
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

        def write(offset, bytes)
          @filesystem.write_inode(@inode_number, offset, bytes)
        end

        def truncate(size = 0)
          @filesystem.truncate_inode(@inode_number, size)
        end

        def create(name, type)
          @filesystem.create_child(@inode_number, name, type)
        end

        def unlink(name)
          @filesystem.unlink_child(@inode_number, name)
        end
      end
    end
  end
end
