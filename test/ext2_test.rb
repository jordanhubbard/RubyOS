# frozen_string_literal: true

require "rubyos"

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

path = ENV.fetch("RUBYOS_EXT2_IMAGE")
device = RubyOS::FS::Ext2::FileBlockDevice.new(path)
filesystem = RubyOS::FS::Ext2.new(device)
vfs = RubyOS::FS::VFS.new
  .mount("/", RubyOS::FS::TmpFS.new.seed("tmp" => {}))
  .mount("/disk", filesystem)

assert(filesystem.block_size == 4096, "ext2 block size")
assert(vfs.readdir("/").include?("disk"), "ext2 mount point visible")
assert(vfs.readdir("/disk").include?("home"), "ext2 root directory")
assert(vfs.read_file("/disk/home/greeting.txt") == "persistent ruby\n", "ext2 file read")
assert(vfs.read_file("/disk/apps/demo/name.txt") == "RubyOS\n", "nested ext2 lookup")
large = vfs.read_file("/disk/home/large.bin")
assert(large.bytesize == 70_000, "single-indirect ext2 file size")
assert(large == "R" * 70_000, "single-indirect ext2 file data")

begin
  vfs.write_file("/disk/home/nope", "denied")
  raise "read-only ext2 accepted a write"
rescue RubyOS::FS::PermissionDenied
  nil
end

device.close
puts "RubyOS ext2 exploration: PASS"
