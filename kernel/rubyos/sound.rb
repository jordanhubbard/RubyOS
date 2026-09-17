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
        build(frequency, duration_ms:, amplitude:, rate:) { |phase| Math.sin(phase * 2.0 * Math::PI) }
      end

      def square(frequency, duration_ms:, amplitude: 0.25, rate: SAMPLE_RATE)
        build(frequency, duration_ms:, amplitude:, rate:) { |phase| phase < 0.5 ? 1.0 : -1.0 }
      end

      def triangle(frequency, duration_ms:, amplitude: 0.25, rate: SAMPLE_RATE)
        build(frequency, duration_ms:, amplitude:, rate:) { |phase| 1.0 - 4.0 * (phase - 0.5).abs }
      end

      def build(frequency, duration_ms:, amplitude:, rate: SAMPLE_RATE)
        frequency = Float(frequency)
        rate = Integer(rate)
        raise ArgumentError, "invalid frequency" unless frequency.finite? && frequency.positive? && frequency <= rate / 2.0
        duration_ms = Float(duration_ms)
        amplitude = Float(amplitude)
        raise ArgumentError, "invalid duration" unless duration_ms.finite? && duration_ms.positive? && duration_ms <= 10_000
        raise ArgumentError, "invalid amplitude" unless amplitude.finite? && (0.0..1.0).cover?(amplitude)

        count = (rate * duration_ms / 1000.0).round
        scale = 32_767 * amplitude
        samples = count.times.map do |index|
          phase = (frequency * index / rate) % 1.0
          (yield(phase) * scale).round
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
        @closed = false
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
        return self if @closed

        @client.call("audio.close")
        @closed = true
        self
      end
    end
  end
end
