# frozen_string_literal: true

module RubyOS
  VERSION = "0.4.0"

  class Error < StandardError; end
  class InvariantError < Error; end

  def self.invariant(condition, message)
    raise InvariantError, message unless condition
  end
end

require "rubyos/scheduler"
require "rubyos/async"
require "rubyos/timekeeper"
require "rubyos/memory"
require "rubyos/input"
require "rubyos/concurrency"
require "rubyos/debug"
require "rubyos/examples"
require "rubyos/sound"
require "rubyos/media"
require "rubyos/app"
require "rubyos/live"
require "rubyos/fs"
require "rubyos/fs/ext2"
require "rubyos/shell"
require "rubyos/driver"
require "rubyos/device"
require "rubyos/drivers/virtio_transport"
require "rubyos/drivers/virtio_block"
require "rubyos/drivers/virtio_net"
require "rubyos/drivers/virtio_sound"
require "rubyos/drivers/hda"
require "rubyos/net/address"
require "rubyos/net/packet"
require "rubyos/net/dhcp"
require "rubyos/net/dns"
require "rubyos/net/tcp"
require "rubyos/net/stack"
require "rubyos/net/repl"
require "rubyos/http"
require "rubyos/gui/text"
require "rubyos/gui/icons"
require "rubyos/gui/ui"
require "rubyos/gui/menu"
require "rubyos/gui/compositor"
require "rubyos/gui/file_dialog"
require "rubyos/apps/application"
require "rubyos/apps/system_apps"
require "rubyos/apps/games"
require "rubyos/apps/ruby_demos"
require "rubyos/apps/graphical_demos"
require "rubyos/apps/catalog"
require "rubyos/bridge/protocol"
require "rubyos/bridge/codec"
require "rubyos/bridge/client"
require "rubyos/bridge/file_transfer"
require "rubyos/bridge/desktop"
require "rubyos/bridge/tcp"
require "rubyos/sdl"
