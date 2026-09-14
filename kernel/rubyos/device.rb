# frozen_string_literal: true

module RubyOS
  class Device
    attr_reader :name, :properties

    def initialize(name, **properties)
      @name = name.freeze
      @properties = properties.freeze
      @driver = nil
    end

    def bind(driver)
      RubyOS.invariant(@driver.nil?, "#{name} already has a driver")
      RubyOS.invariant(driver.supports?(self), "#{driver.class} rejects #{name}")
      @driver = driver
      driver.attach(self)
      self
    end

    def driver
      @driver
    end

    def bound?
      !@driver.nil?
    end
  end

  class Bus
    include Enumerable

    def initialize
      @devices = []
    end

    def each(&block)
      @devices.each(&block)
    end

    def add(device)
      @devices << device
      device
    end

    def bind(drivers)
      each do |device|
        driver = drivers.lazy.map(&:new).find { |candidate| candidate.supports?(device) }
        device.bind(driver) if driver
      end
    end
  end
end
