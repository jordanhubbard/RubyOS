# frozen_string_literal: true

module RubyOS
  module GUI
    # Anti-aliased text for every surface the compositor paints.
    #
    # The bridge has always exposed SDL_ttf (Bridge::Font), but the GUI drew
    # exclusively through +text.draw+ -- the embedded 8x8 bitmap font, one
    # SDL_FillRect per lit pixel, ASCII only. This module routes the same
    # +draw_text+ calls through TTF instead and keeps the bitmap path as the
    # fallback for hosts with no usable font.
    #
    # Layout compatibility is the constraint that shapes everything here. The
    # widget code is full of +/ 8+ and +* 8+ column arithmetic, so the renderer
    # only engages with a *monospace* face and publishes the measured advance
    # as GUI::Text.advance for those call sites to use. On macOS the host
    # offers Menlo, whose advance is exactly 8px at 14pt -- the same grid the
    # bitmap font used, now anti-aliased.
    #
    # Rendered runs are cached host-side as (text, color) => Surface and
    # blitted on subsequent frames, so a steady desktop costs one blit per
    # string per frame rather than one fill per pixel.
    module Text
      # 14pt keeps Menlo's advance at 8px -- see the note above on why the
      # advance, not the point size, is the number that has to stay put.
      DEFAULT_POINT_SIZE = 14
      # Metrics of the embedded 8x8 face, used until a TTF font is measured
      # and again if one can never be opened.
      BITMAP_ADVANCE = 8
      BITMAP_HEIGHT = 8
      # Distinct (text, color) runs held host-side. Chrome and a few screens
      # of body text sit far below this; the cap bounds a terminal scrolling
      # unique output forever.
      CACHE_LIMIT = 2_048

      # A face whose glyphs are not all one width would silently break every
      # column calculation in ui.rb, so we verify rather than assume. The
      # probe spans the narrowest and widest glyphs a proportional face would
      # disagree on.
      PROPORTIONAL_PROBE = %w[i M 0 W].freeze
      PROBE_RUN = 16

      class << self
        attr_reader :point_size

        # Open the host's default font against +client+ and measure it.
        # Returns true when subsequent draws will be anti-aliased. Safe to
        # call repeatedly; re-opens if the client changed.
        def enable!(client, point_size: DEFAULT_POINT_SIZE)
          point_size = Integer(point_size)
          return available? if @client.equal?(client) && @point_size == point_size

          disable!
          @client = client
          @point_size = point_size
          @font = Bridge::Font.open_default(client, point_size:)
          @advance, @height = measure_face(@font)
          @cache = {}
          true
        rescue StandardError => error
          # No font is a downgrade, never a boot failure.
          @failure = "#{error.class}: #{error.message}"
          disable!
          false
        end

        # Drop the font and every cached run. Draws fall back to the bitmap
        # path until #enable! succeeds again.
        def disable!
          @cache&.each_value(&:destroy)
          @font&.close
          @cache = nil
          @font = nil
          @client = nil
          @point_size = nil
          @advance = nil
          @height = nil
          self
        rescue StandardError
          # Freeing host resources is best-effort: by the time we get here the
          # transport may already be closed, and a teardown that raises would
          # strand the renderer in a half-enabled state.
          @cache = nil
          @font = nil
          @client = nil
          @advance = nil
          @height = nil
          self
        end

        def available? = !@font.nil?

        # Why the renderer is off, or nil if it was never tried / is on.
        attr_reader :failure

        # Horizontal advance of one glyph cell, in pixels. Widget column
        # arithmetic must use this instead of a literal 8.
        def advance = @advance || BITMAP_ADVANCE

        # Height of a rendered glyph box, in pixels.
        def height = @height || BITMAP_HEIGHT

        # Columns that fit in +pixels+ of horizontal space.
        def columns_for(pixels) = [Integer(pixels) / advance, 0].max

        # Pixel width of +text+ on the current face.
        def width(text) = String(text).each_char.count * advance

        def measure(text) = [width(text), height]

        # Longest prefix of +text+ that fits within +max_pixels+.
        def truncate(text, max_pixels)
          text = String(text)
          columns = columns_for(max_pixels)
          columns >= text.each_char.count ? text : text.each_char.first(columns).join
        end

        # Paint +text+ onto +surface+ at (+x+, +y+), matching the placement
        # the 8x8 bitmap path would have produced so existing layouts hold.
        # Returns the [width, height] drawn.
        def draw(surface, x, y, text, color: 0xffffff, background: nil)
          text = String(text)
          return bitmap_draw(surface, x, y, text, color:, background:) unless available?

          # The bitmap path treats "\n" as a line break; TTF rendering does
          # not, so split here to keep the two paths interchangeable.
          if text.include?("\n")
            drawn_width = 0
            text.split("\n", -1).each_with_index do |line, index|
              line_width, = draw(surface, x, y + index * height, line, color:, background:)
              drawn_width = [drawn_width, line_width].max
            end
            return [drawn_width, text.count("\n").succ * height]
          end
          return [0, height] if text.empty?

          glyphs = cached_run(text, color)
          return bitmap_draw(surface, x, y, text, color:, background:) unless glyphs

          # Anti-aliased glyph boxes are taller than the 8px cells callers
          # positioned against, so centre the run on the cell's midline
          # rather than letting it hang below the intended baseline.
          offset_y = (BITMAP_HEIGHT - glyphs.height) / 2
          surface.fill_rect(x, y + offset_y, glyphs.width, glyphs.height, background) if background
          glyphs.blit_to(surface, x:, y: y + offset_y)
          [glyphs.width, glyphs.height]
        rescue StandardError => error
          # A dead font handle must not take the desktop down with it.
          @failure = "#{error.class}: #{error.message}"
          disable!
          bitmap_draw(surface, x, y, text, color:, background:)
        end

        private

        def bitmap_draw(surface, x, y, text, color:, background:)
          surface.draw_bitmap_text(x, y, text, color:, background:)
          [String(text).each_char.count * BITMAP_ADVANCE, BITMAP_HEIGHT]
        end

        # Rendered runs are immutable, so a plain insertion-ordered Hash gives
        # us LRU-ish eviction for free: re-inserting on hit moves an entry to
        # the young end and #shift drops the oldest.
        def cached_run(text, color)
          key = [text, Integer(color)]
          if (hit = @cache.delete(key))
            @cache[key] = hit
            return hit
          end
          rendered = @font.render(text, color:)
          @cache[key] = rendered
          @cache.shift.last.destroy while @cache.length > CACHE_LIMIT
          rendered
        end

        # Reject a proportional face: its glyphs would drift out of the
        # column grid every widget here assumes.
        #
        # Advance is derived by differencing two runs of the same glyph rather
        # than measuring one. TTF_SizeUTF8 reports ink extent, so a run ending
        # in "W" comes back a pixel wider than its advances even on a fixed
        # -pitch face; that overhang depends only on the final glyph, so it is
        # identical in both runs and cancels exactly in the difference.
        def measure_face(font)
          advances = PROPORTIONAL_PROBE.map do |glyph|
            short, = font.measure(glyph * PROBE_RUN)
            long, = font.measure(glyph * (PROBE_RUN * 2))
            long - short
          end
          raise RubyOS::Error, "host default font is not monospace" unless advances.uniq.one?

          advance = advances.first / PROBE_RUN
          raise RubyOS::Error, "host default font is not monospace" unless
            advances.first == advance * PROBE_RUN
          raise RubyOS::Error, "host default font has no usable advance" unless advance.positive?

          [advance, font.measure(PROPORTIONAL_PROBE.join).last]
        end
      end
    end
  end
end
