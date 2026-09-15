# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_native_audio
      HAL.serial_write("[RubyOS] native audio probe\n")
      output = if HAL.respond_to?(:pci_read32)
                 Drivers::HDA.find
               else
                 Drivers::VirtioSound.find
               end
      RubyOS.invariant(output, "native sound device was not discovered")
      HAL.serial_write("[RubyOS] native audio device ready\n")
      samples = Array.new(480) { |index| (index / 24).even? ? 3_000 : -3_000 }
      tone = Sound::PCM.new(samples)
      written = output.play(tone)
      RubyOS.invariant(written == tone.stereo_bytes.bytesize, "native PCM write was incomplete")
      backend = output.is_a?(Drivers::HDA) ? "HDA" : "VirtIO"
      HAL.serial_write("[RubyOS] native #{backend} sound DMA: PASS\n")
      true
    end
  end
end
