# frozen_string_literal: true

module RubyOS
  VERSION = "0.0.1"

  class Error < StandardError; end
  class InvariantError < Error; end

  def self.invariant(condition, message)
    raise InvariantError, message unless condition
  end
end

require "rubyos/scheduler"
require "rubyos/timekeeper"
require "rubyos/fs"
require "rubyos/fs/ext2"
require "rubyos/shell"
require "rubyos/driver"
require "rubyos/device"
require "rubyos/drivers/virtio_block"
require "rubyos/drivers/virtio_net"
require "rubyos/net/address"
require "rubyos/net/packet"
require "rubyos/net/tcp"
require "rubyos/net/stack"
require "rubyos/gui/ui"
require "rubyos/bridge/protocol"
require "rubyos/bridge/codec"
require "rubyos/bridge/client"
require "rubyos/bridge/desktop"
require "rubyos/bridge/tcp"
