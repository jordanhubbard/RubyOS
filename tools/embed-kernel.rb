# frozen_string_literal: true

root = File.expand_path("..", __dir__)
paths = %w[
  kernel/rubyos.rb
  kernel/rubyos/scheduler.rb
  kernel/rubyos/timekeeper.rb
  kernel/rubyos/fs.rb
  kernel/rubyos/fs/ext2.rb
  kernel/rubyos/shell.rb
  kernel/rubyos/driver.rb
  kernel/rubyos/device.rb
  kernel/rubyos/drivers/virtio_block.rb
  kernel/rubyos/drivers/virtio_net.rb
  kernel/rubyos/net/address.rb
  kernel/rubyos/net/packet.rb
  kernel/rubyos/net/tcp.rb
  kernel/rubyos/net/stack.rb
  kernel/rubyos/gui/ui.rb
  kernel/rubyos/bridge/protocol.rb
  kernel/rubyos/bridge/codec.rb
  kernel/rubyos/bridge/client.rb
  kernel/rubyos/bridge/desktop.rb
  kernel/rubyos/bridge/virtio_console.rb
  kernel/boot.rb
  kernel/storage_boot.rb
  kernel/network_boot.rb
  kernel/gui_boot.rb
]

source = paths.map do |path|
  File.readlines(File.join(root, path)).reject do |line|
    line.match?(/^require "rubyos(?:\/|"$)/)
  end.join
end.join("\n")
source << "\nRubyOS::Kernel.boot\n"
if ENV["RUBYOS_EMBED_STORAGE"] == "1"
  source << "RubyOS::Kernel.mount_persistent_storage\n"
end
if ENV["RUBYOS_EMBED_NETWORK"] == "1"
  source << "RubyOS::Kernel.boot_network\n"
end
if ENV["RUBYOS_EMBED_DESKTOP"] == "1"
  source << "RubyOS::Kernel.boot_remote_desktop\n"
end
if ENV["RUBYOS_EMBED_REPL"] == "1"
  source << "RubyOS::Shell.new.run\n"
end

puts "/* Generated from RubyOS kernel sources. */"
puts "static const char rubyos_kernel_source[] = {"
source.bytes.each_slice(16) do |bytes|
  puts "    #{bytes.map { |byte| format('0x%02x', byte) }.join(', ')},"
end
puts "    0x00"
puts "};"
