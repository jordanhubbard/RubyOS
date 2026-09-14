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
require "rubyos/shell"
require "rubyos/driver"
require "rubyos/device"
require "rubyos/gui/ui"
require "rubyos/bridge/protocol"
require "rubyos/bridge/codec"
require "rubyos/bridge/client"
require "rubyos/bridge/desktop"
require "rubyos/bridge/tcp"
