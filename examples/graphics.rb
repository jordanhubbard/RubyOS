# frozen_string_literal: true

# The compositor targets a tiny drawing protocol, so the same Ruby scene can
# render through SDL, a framebuffer, or this inspectable teaching surface.
require "rubyos"

surface = Object.new
operations = []
surface.define_singleton_method(:fill_rect) { |*values| operations << [:fill, *values] }
surface.define_singleton_method(:draw_text) { |*values, **options| operations << [:text, *values, options] }
desktop = RubyOS::GUI::Compositor.new(width: 320, height: 200, title: "Lesson")
window = RubyOS::GUI::Window.new("Ruby Graphics", x: 60, y: 40, width: 190, height: 100)
window.add(RubyOS::GUI::Label.new("Objects become pixels", x: 4, y: 8))
desktop.add_window(window)
desktop.draw(surface)
puts "graphics lesson: #{operations.length} drawing operations"
puts "graphics lesson: PASS"
