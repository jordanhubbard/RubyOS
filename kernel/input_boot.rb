# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_native_input
      keyboard = Input::PS2Keyboard.new if HAL.respond_to?(:ps2_scancode)
      virtio = Input::VirtioMMIO.find_all unless keyboard
      RubyOS.invariant(keyboard || !virtio.empty?, "native input device was not discovered")
      got_key = false
      got_pointer = keyboard ? true : false
      deadline = HAL.monotonic_ns + 5_000_000_000
      while HAL.monotonic_ns < deadline
        events = if keyboard
                   scancode = HAL.ps2_scancode
                   scancode ? [keyboard.feed(scancode)].compact : []
                 else
                   virtio.flat_map(&:poll)
                 end
        events.each do |event|
          got_key = true if event.kind == Input::KEY_DOWN && event.text == "r"
          got_pointer = true if event.kind == Input::POINTER_MOVE && !event.dx.zero?
          if got_key && got_pointer
            backend = keyboard ? "PS/2" : "VirtIO"
            HAL.serial_write("[RubyOS] native #{backend} input: PASS\n")
            return true
          end
        end
        HAL.sleep_us(1_000)
      end
      raise RubyOS::Error, "native input timed out"
    end
  end
end
