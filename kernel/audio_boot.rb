# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_native_audio
      output = Drivers::VirtioSound.find
      RubyOS.invariant(output, "VirtIO sound device was not discovered")
      tone = Sound::Waveform.sine(440, duration_ms: 40, amplitude: 0.1)
      written = output.play(tone)
      RubyOS.invariant(written == tone.stereo_bytes.bytesize, "native PCM write was incomplete")
      HAL.serial_write("[RubyOS/arm64] native VirtIO sound DMA: PASS\n")
      true
    end
  end
end
