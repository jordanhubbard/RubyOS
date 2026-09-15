# frozen_string_literal: true

# RubyOS reloads applications through an anonymous Module. A syntax or runtime
# failure leaves the previous class alive; success swaps a fresh Ruby object
# into the registry without pretending Ruby has a portable module ABI.
require "rubyos"
require_relative "../kernel/boot"

state = RubyOS::Kernel.boot(output: File.open(File::NULL, "w"))
registry = RubyOS::Apps::Registry.new
runtime = RubyOS::Live::Runtime.new(vfs: state.fetch(:vfs), registry:)
runtime.install("Lesson", path: "/apps/lesson.rb", source: <<~RUBY)
  class App < RubyOS::Apps::Application
    def message = "a fresh class from a Module sandbox"
    def build_window = RubyOS::GUI::Window.new(message, width: 200, height: 80)
  end
RUBY
puts "live_ruby lesson: #{registry.fetch('Lesson').message}"
puts "live_ruby lesson: PASS"
