# frozen_string_literal: true

module RubyOS
  module Kernel
    module_function

    def boot_remote_desktop
      transport = Bridge::Transport::VirtioConsole.find
      client = Bridge::Client.new(transport)
      hello = client.hello
      RubyOS.invariant(hello.fetch("agent") == "rubyos_bridge",
                       "unexpected remote desktop agent")

      desktop = Bridge::RemoteDesktop.new(client, width: 480, height: 300,
                                           title: "RubyOS Bare-Metal Desktop")
      root = GUI::Container.new(x: 0, y: 0, width: 480, height: 300,
                                background: 0x171321)
      root.add(GUI::View.new(x: 24, y: 24, width: 432, height: 252,
                             background: 0x3b245c))
      root.add(GUI::View.new(x: 36, y: 58, width: 408, height: 196,
                             background: 0x21182f))
      root.add(GUI::Label.new("Ruby owns this bare-metal desktop",
                              x: 52, y: 78, color: 0xffd866))
      root.add(GUI::Label.new("CRuby 4 + Prism + VirtIO + SDL",
                              x: 52, y: 104, color: 0x9cdcfe))
      root.draw(desktop.surface)
      desktop.present
      desktop.capture("/tmp/rubyos-baremetal-desktop.bmp")
      desktop.close
      client.call("shutdown")
      client.close
      RubyOS::HAL.serial_write("[RubyOS/arm64] remote SDL desktop: PASS\n")
      true
    end
  end
end
