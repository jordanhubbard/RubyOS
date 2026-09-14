# frozen_string_literal: true

# Waveforms and mixing stay in Ruby; only final signed PCM crosses to SDL.
require "rubyos"

mixer = RubyOS::Sound::Mixer.new
chord = mixer.mix(RubyOS::Sound::Waveform.sine(220, duration_ms: 25, amplitude: 0.2),
                  RubyOS::Sound::Waveform.sine(330, duration_ms: 25, amplitude: 0.2))
puts "audio lesson: #{chord.frames} stereo frames, #{chord.stereo_bytes.bytesize} bytes"
puts "audio lesson: PASS"
