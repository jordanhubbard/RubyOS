# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_native_input
      keyboard = Input::PS2Keyboard.new
      deadline = HAL.monotonic_ns + 5_000_000_000
      while HAL.monotonic_ns < deadline
        if (scancode = HAL.ps2_scancode)
          event = keyboard.feed(scancode)
          if event&.kind == Input::KEY_DOWN && event.text == "r"
            HAL.serial_write("[RubyOS/x86_64] native PS/2 input: PASS\n")
            return true
          end
        end
        HAL.sleep_us(1_000)
      end
      raise RubyOS::Error, "native PS/2 input timed out"
    end
  end
end
