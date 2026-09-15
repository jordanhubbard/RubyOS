# frozen_string_literal: true

root = File.expand_path("..", __dir__)
paths = %w[
  kernel/rubyos.rb
  kernel/rubyos/scheduler.rb
  kernel/rubyos/timekeeper.rb
  kernel/rubyos/memory.rb
  kernel/rubyos/input.rb
  kernel/rubyos/concurrency.rb
  kernel/rubyos/debug.rb
  kernel/rubyos/sound.rb
  kernel/rubyos/chipset.rb
  kernel/rubyos/live.rb
  kernel/rubyos/fs.rb
  kernel/rubyos/fs/ext2.rb
  kernel/rubyos/shell.rb
  kernel/rubyos/driver.rb
  kernel/rubyos/device.rb
  kernel/rubyos/drivers/virtio_block.rb
  kernel/rubyos/drivers/virtio_net.rb
  kernel/rubyos/drivers/virtio_sound.rb
  kernel/rubyos/drivers/hda.rb
  kernel/rubyos/net/address.rb
  kernel/rubyos/net/packet.rb
  kernel/rubyos/net/dhcp.rb
  kernel/rubyos/net/dns.rb
  kernel/rubyos/net/tcp.rb
  kernel/rubyos/net/stack.rb
  kernel/rubyos/net/repl.rb
  kernel/rubyos/http.rb
  kernel/rubyos/gui/ui.rb
  kernel/rubyos/gui/compositor.rb
  kernel/rubyos/apps/application.rb
  kernel/rubyos/apps/system_apps.rb
  kernel/rubyos/apps/games.rb
  kernel/rubyos/bridge/protocol.rb
  kernel/rubyos/bridge/codec.rb
  kernel/rubyos/bridge/client.rb
  kernel/rubyos/bridge/desktop.rb
  kernel/rubyos/bridge/virtio_console.rb
  kernel/rubyos/bridge/native_tcp.rb
  kernel/boot.rb
  kernel/storage_boot.rb
  kernel/network_boot.rb
  kernel/web_boot.rb
  kernel/gui_boot.rb
  kernel/input_boot.rb
  kernel/audio_boot.rb
  kernel/smp_boot.rb
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
if ENV["RUBYOS_EMBED_WEB"] == "1"
  source << "RubyOS::Kernel.boot_web\n"
end
if ENV["RUBYOS_EMBED_DESKTOP"] == "1"
  source << "RubyOS::Kernel.boot_remote_desktop\n"
end
if ENV["RUBYOS_EMBED_DESKTOP_TCP"] == "1"
  source << "RubyOS::Kernel.boot_remote_desktop_tcp\n"
end
if ENV["RUBYOS_EMBED_REPL"] == "1"
  source << "RubyOS::Shell.new.run\n"
end
if ENV["RUBYOS_EMBED_INTERACTIVE_DESKTOP"] == "1"
  source << "RubyOS::Kernel.boot_remote_desktop_tcp(interactive: true)\n"
end
if ENV["RUBYOS_EMBED_INPUT"] == "1"
  source << "RubyOS::Kernel.boot_native_input\n"
end
if ENV["RUBYOS_EMBED_AUDIO"] == "1"
  source << "RubyOS::Kernel.boot_native_audio\n"
end
if ENV["RUBYOS_EMBED_SMP"] == "1"
  source << "RubyOS::Kernel.boot_smp\n"
end

puts "/* Generated from RubyOS kernel sources. */"
puts "static const char rubyos_kernel_source[] = {"
source.bytes.each_slice(16) do |bytes|
  puts "    #{bytes.map { |byte| format('0x%02x', byte) }.join(', ')},"
end
puts "    0x00"
puts "};"
