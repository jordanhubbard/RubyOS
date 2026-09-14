# frozen_string_literal: true

module RubyOS
  class Resource
    attr_reader :start, :length

    def initialize(start, length)
      @start = Integer(start)
      @length = Integer(length)
      raise ArgumentError, "resource length must be positive" unless @length.positive?
    end

    def finish = start + length - 1
    def cover?(address) = Integer(address).between?(start, finish)
  end

  class MMIOResource < Resource; end
  class PortResource < Resource; end

  class IRQResource
    attr_reader :number

    def initialize(number)
      @number = Integer(number)
      raise ArgumentError, "IRQ number must be non-negative" if @number.negative?
    end
  end

  class Device
    attr_reader :name, :properties, :resources, :parent

    def initialize(name, resources: [], parent: nil, **properties)
      @name = String(name).freeze
      @properties = properties.freeze
      @resources = resources.freeze
      @parent = parent
      @driver = nil
    end

    def [](property) = properties.fetch(property)

    def bind(driver)
      RubyOS.invariant(@driver.nil?, "#{name} already has a driver")
      RubyOS.invariant(driver.supports?(self), "#{driver.class} rejects #{name}")
      return false unless driver.probe(self)

      @driver = driver
      self
    end

    def unbind
      return false unless @driver

      bound_driver = @driver
      bound_driver.remove(self)
      @driver = nil
      bound_driver
    end

    def driver = @driver
    def bound? = !@driver.nil?
  end

  class PlatformDevice < Device; end

  class PCIDevice < Device
    def initialize(name, vendor_id:, device_id:, class_code:, **properties)
      super(name, vendor_id: Integer(vendor_id), device_id: Integer(device_id),
            class_code:, **properties)
    end

    def id = format("%04x:%04x", properties[:vendor_id], properties[:device_id])
  end

  class Bus
    include Enumerable

    Registration = Data.define(:driver_class, :properties, :priority) do
      def score = properties.length * 100 + priority

      def matches?(device)
        properties.all? { |key, value| device.properties[key] == value }
      end
    end

    def initialize(enumerators: [])
      @devices = []
      @enumerators = Array(enumerators)
      @registrations = []
    end

    def each(&block) = @devices.each(&block)
    def length = @devices.length

    def add(device)
      RubyOS.invariant(device.is_a?(Device), "bus accepts only Device objects")
      RubyOS.invariant(@devices.none? { |known| known.name == device.name },
                       "duplicate device #{device.name}")
      @devices << device
      device
    end

    def enumerate
      @enumerators.each do |enumerator|
        Array(enumerator.call).each { |device| add(device) }
      end
      self
    end

    def register_driver(driver_class, priority: nil, **properties)
      declared = driver_class.respond_to?(:match_properties) ? driver_class.match_properties : {}
      match = declared.merge(properties).freeze
      raise ArgumentError, "driver registration needs match properties" if match.empty?

      rank = priority.nil? && driver_class.respond_to?(:priority) ? driver_class.priority : Integer(priority || 0)
      @registrations << Registration.new(driver_class:, properties: match, priority: rank)
      self
    end

    def bind_drivers
      each do |device|
        next if device.bound?

        candidates = @registrations.select { |registration| registration.matches?(device) }
                                   .sort_by { |registration| -registration.score }
        candidates.each do |registration|
          break if device.bind(registration.driver_class.new)
        end
      end
      self
    end

    def bind(drivers)
      drivers.each { |driver_class| register_driver(driver_class) }
      bind_drivers
    end

    def find(**properties)
      select { |device| properties.all? { |key, value| device.properties[key] == value } }
    end

    def find_by_id(vendor_id, device_id)
      find(vendor_id: Integer(vendor_id), device_id: Integer(device_id))
    end

    def topology
      map do |device|
        parent = device.parent ? " below=#{device.parent.name}" : ""
        driver = device.bound? ? device.driver.class.to_s : "unbound"
        "#{device.name}#{parent} driver=#{driver}"
      end.freeze
    end

    def remove(device)
      return false unless @devices.include?(device)

      device.unbind
      @devices.delete(device)
      device
    end
  end
end
