# frozen_string_literal: true

module RubyOS
  module Driver
    attr_reader :device

    def attach(device)
      @device = device
      self
    end
  end

  class SerialDriver
    include Driver

    def supports?(device)
      device.properties[:kind] == :serial
    end
  end
end
