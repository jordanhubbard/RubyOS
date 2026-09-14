# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def mount_persistent_storage(output: $stdout)
      device = Drivers::VirtioBlock.find
      filesystem = FS::Ext2.new(device)
      vfs = state.fetch(:vfs)
      vfs.mount("/home", FS::NodeFS.new(filesystem.root.lookup("home")))
      vfs.mount("/apps", FS::NodeFS.new(filesystem.root.lookup("apps")))
      output.puts "storage: ext2 #{device.sector_count} sectors mounted at /home and /apps"
      filesystem
    end
  end
end
