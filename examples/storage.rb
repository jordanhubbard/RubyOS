# frozen_string_literal: true

# RubyOS storage is ordinary object composition: mount filesystems into a VFS,
# then use descriptor operations or convenient whole-file methods.
require "rubyos"

root = RubyOS::FS::TmpFS.new.seed("home" => {})
vfs = RubyOS::FS::VFS.new.mount("/", root)
descriptor = vfs.open("/home/lesson.txt",
                      RubyOS::FS::OpenFlags::CREATE | RubyOS::FS::OpenFlags::READ_WRITE)
vfs.write(descriptor, "Ruby objects persist bytes.")
vfs.seek(descriptor, 0)
puts vfs.read(descriptor, 64)
vfs.close(descriptor)
vfs.unlink("/home/lesson.txt")
puts "storage lesson: PASS" unless vfs.readdir("/home").include?("lesson.txt")
