# frozen_string_literal: true

module RubyOS
  module Sound
    SAMPLE_RATE = 48_000

    class PCM
      attr_reader :samples, :rate

      def initialize(samples, rate: SAMPLE_RATE)
        @samples = samples.map { |sample| [[Integer(sample), 32_767].min, -32_768].max }.freeze
        @rate = Integer(rate)
      end

      def frames
        samples.length
      end

      def stereo_bytes
        samples.flat_map { |sample| [sample, sample] }.pack("s<*")
      end
    end

    module Waveform
      module_function

      def sine(frequency, duration_ms:, amplitude: 0.25, rate: SAMPLE_RATE)
        count = (rate * duration_ms / 1000.0).round
        scale = 32_767 * Float(amplitude)
        samples = count.times.map do |index|
          (Math.sin(2.0 * Math::PI * Float(frequency) * index / rate) * scale).round
        end
        PCM.new(samples, rate:)
      end
    end

    class Mixer
      def mix(*voices)
        raise ArgumentError, "at least one voice required" if voices.empty?
        rate = voices.first.rate
        raise ArgumentError, "sample rates do not match" unless voices.all? { |voice| voice.rate == rate }
        length = voices.map(&:frames).max
        samples = length.times.map do |index|
          value = voices.sum { |voice| voice.samples[index] || 0 }
          [[value, 32_767].min, -32_768].max
        end
        PCM.new(samples, rate:)
      end
    end

    class BridgeOutput
      def initialize(client, rate: SAMPLE_RATE)
        @client = client
        result = client.call("audio.open", { rate: })
        @rate = result.fetch("rate")
      end

      def play(pcm)
        raise ArgumentError, "sample rate mismatch" unless pcm.rate == @rate
        @client.call("audio.queue", {}, payload: pcm.stereo_bytes)
        self
      end

      def queued_bytes
        @client.call("audio.status").fetch("queued_bytes")
      end

      def close
        @client.call("audio.close")
        self
      end
    end
  end
end
