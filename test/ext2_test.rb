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

vfs.write_file("/disk/home/created.txt", "written by Ruby")
assert(vfs.read_file("/disk/home/created.txt") == "written by Ruby", "ext2 create and write")
vfs.write_file("/disk/home/created.txt", "replacement")
assert(vfs.read_file("/disk/home/created.txt") == "replacement", "ext2 truncate and rewrite")
vfs.mkdir("/disk/home/projects")
vfs.write_file("/disk/home/projects/readme", "nested write")
assert(vfs.read_file("/disk/home/projects/readme") == "nested write", "ext2 directory creation")
vfs.unlink("/disk/home/created.txt")
begin
  vfs.stat("/disk/home/created.txt")
  raise "unlinked ext2 file remained visible"
rescue RubyOS::FS::NotFound
end
vfs.mkdir("/disk/home/temporary")
vfs.unlink("/disk/home/temporary")
assert(!vfs.readdir("/disk/home").include?("temporary"), "empty ext2 directory removal")
begin
  vfs.unlink("/disk/home/projects")
  raise "nonempty ext2 directory was removed"
rescue RubyOS::FS::Error
end
vfs.write_file("/disk/home/truncate.bin", "x" * 8192)
truncate_node = filesystem.root.lookup("home").lookup("truncate.bin")
truncate_node.truncate(100)
assert(truncate_node.read(0, 200) == "x" * 100, "ext2 partial truncate")
truncate_node.write(200, "Z")
assert(truncate_node.read(99, 102) == "x" + "\0" * 100 + "Z", "ext2 sparse extension")
double_offset = (12 + filesystem.block_size / 4) * filesystem.block_size + 17
truncate_node.write(double_offset, "double")
assert(truncate_node.read(double_offset, 6) == "double", "double-indirect ext2 write")
truncate_node.truncate(100)
assert(truncate_node.stat.size == 100, "double-indirect ext2 truncate size")

device.close

device = RubyOS::FS::Ext2::FileBlockDevice.new(path)
filesystem = RubyOS::FS::Ext2.new(device)
begin
  filesystem.root.lookup("home").lookup("created.txt")
  raise "ext2 deletion did not survive remount"
rescue RubyOS::FS::NotFound
end
assert(filesystem.root.lookup("home").lookup("projects").lookup("readme").read(0, 32) == "nested write",
       "ext2 directory survives remount")
device.close
puts "RubyOS ext2 exploration: PASS"
