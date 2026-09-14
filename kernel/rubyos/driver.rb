# frozen_string_literal: true

module RubyOS
  module Driver
    module ClassMethods
      def matches(**properties)
        @match_properties = properties.freeze
      end

      def match_properties
        @match_properties || {}.freeze
      end

      def priority(value = nil)
        @priority = Integer(value) unless value.nil?
        @priority || 0
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    attr_reader :device

    def supports?(candidate)
      self.class.match_properties.all? { |key, value| candidate.properties[key] == value }
    end

    def attach(candidate)
      RubyOS.invariant(@device.nil?, "#{self.class} is already attached")
      @device = candidate
      self
    end

    def probe(candidate)
      attach(candidate)
      true
    end

    def remove(candidate)
      RubyOS.invariant(@device.equal?(candidate), "#{self.class} is not attached to #{candidate.name}")
      @device = nil
      nil
    end
  end

  class SerialDriver
    include Driver
    matches kind: :serial
    priority 10
  end
end
