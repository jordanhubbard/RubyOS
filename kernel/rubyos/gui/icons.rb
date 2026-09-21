# frozen_string_literal: true

module RubyOS
  module GUI
    # Procedural dock icons.
    #
    # The dock used to paint text labels in boxes; these give it the square
    # icons a desktop is expected to have. They are drawn rather than loaded
    # so the guest carries no image assets: kernel sources are embedded as a
    # C string literal and have to stay 7-bit ASCII, which would make a
    # baked-in PNG cost several times its own size in hex.
    #
    # Each icon is declared as rectangles and lines on a 48x48 grid and
    # rendered to whatever the dock asks for, so a compact desktop gets a
    # genuinely smaller icon rather than a scaled-down blur. Rendered bitmaps
    # are memoised per (name, size) and never mutated, so
    # Bridge::Surface#draw_bitmap uploads each once and blits it thereafter.
    module Icons
      # The coordinate space every SPECS entry is written in.
      GRID = 48
      SIZE = 48

      # Tints for generated placeholders, spaced so neighbours stay apart.
      DEFAULT_TINTS = [0x3b245c, 0x1f3a5c, 0x2f4a2a, 0x5c3320,
                       0x4a2444, 0x1f4a4a, 0x4a4420, 0x33335c].freeze

      # name => { background:, border:, rects: [[x, y, w, h, colour], ...],
      #           lines: [[x0, y0, x1, y1, colour], ...] }
      SPECS = {
        # A 3x3 tile grid: "all applications".
        "Launcher" => {
          background: 0x241631, border: 0x553184,
          rects: (0..2).flat_map { |row| (0..2).map { |col| [8 + col * 12, 8 + row * 12, 8, 8, 0x9b6dff] } }
        },
        # Folder: tab above, body below.
        "Files" => {
          background: 0x1b1526, border: 0x8a6320,
          rects: [[8, 12, 14, 5, 0xe0b040], [6, 16, 36, 22, 0xf0c050]]
        },
        # Shell prompt: a chevron and a cursor rule.
        "Terminal" => {
          background: 0x0b0f0b, border: 0x2f7a2f,
          rects: [[24, 27, 14, 3, 0x2f7a2f]],
          lines: [[11, 16, 19, 23, 0x60ff60], [11, 30, 19, 23, 0x60ff60]]
        },
        # A page of text.
        "Editor" => {
          background: 0xe4e4ec, border: 0x45454f,
          rects: [[9, 12, 30, 3, 0x303038], [9, 21, 30, 3, 0x303038], [9, 30, 18, 3, 0x303038]]
        },
        # Magnifier over a sample field.
        "Inspector" => {
          background: 0x111522, border: 0x2b3c5c,
          rects: [[10, 10, 20, 20, 0x1f3350], [10, 10, 20, 2, 0x78dce8],
                  [10, 28, 20, 2, 0x78dce8], [10, 10, 2, 20, 0x78dce8],
                  [28, 10, 2, 20, 0x78dce8]],
          lines: [[29, 29, 38, 38, 0x78dce8], [31, 28, 39, 36, 0x78dce8]]
        },
        # Ascending bar chart.
        "Monitor" => {
          background: 0x10141f, border: 0x2b3c5c,
          rects: [[10, 24, 5, 14, 0x78dce8], [17, 16, 5, 22, 0x78dce8],
                  [24, 28, 5, 10, 0x78dce8], [31, 20, 5, 18, 0x78dce8]]
        },
        # Lowercase "i", for information.
        "About" => {
          background: 0x21182f, border: 0x553184,
          rects: [[22, 10, 5, 5, 0xffd866], [22, 19, 5, 19, 0xffd866]]
        },
        # Clock face with two hands.
        "Clock" => {
          background: 0x151a26, border: 0x3a3350,
          rects: [[8, 8, 32, 2, 0xd8cae5], [8, 38, 32, 2, 0xd8cae5],
                  [8, 8, 2, 32, 0xd8cae5], [38, 8, 2, 32, 0xd8cae5]],
          lines: [[24, 24, 24, 14, 0xffd866], [24, 24, 32, 28, 0xff668a]]
        },
        # Three sliders at different settings.
        "Settings" => {
          background: 0x181428, border: 0x553184,
          rects: [[8, 14, 32, 2, 0x554a6b], [10, 11, 6, 8, 0xb792ff],
                  [8, 24, 32, 2, 0x554a6b], [21, 21, 6, 8, 0xb792ff],
                  [8, 34, 32, 2, 0x554a6b], [32, 31, 6, 8, 0xb792ff]]
        },
        # Keyboard: three rows of keys over a space bar.
        "Keybindings" => {
          background: 0x1a1a28, border: 0x50506a,
          rects: (0..2).flat_map { |row| (0..4).map { |col| [7 + col * 7, 12 + row * 7, 5, 5, 0xd0d0d8] } } +
                 [[13, 33, 22, 4, 0xd0d0d8]]
        },
        # Framed landscape: sun over ground.
        "Image" => {
          background: 0x2a1840, border: 0x80408c,
          rects: [[8, 8, 32, 32, 0xc0c0e0], [28, 12, 8, 8, 0xffd040], [8, 30, 32, 10, 0x40a040]]
        },
        # Colour bars, the test-pattern motif.
        "Media" => {
          background: 0x101018, border: 0xe0e0e0,
          rects: [0xc00000, 0xc0c000, 0x00c000, 0x00c0c0, 0x0000c0, 0xc000c0]
                   .each_with_index.map { |color, index| [index * 8, 8, 8, 32, color] }
        }
      }.freeze

      module_function

      # The icon for +name+ at +size+ pixels square, generating a placeholder
      # for apps without a dedicated one. Memoised: the dock asks every frame.
      def for(name, size: SIZE)
        name = String(name)
        size = Integer(size)
        @cache ||= {}
        @cache[[name, size]] ||= render(SPECS[name] || placeholder_spec(name), size)
      end

      # True when +name+ has no dedicated icon, so the dock knows to overlay
      # the app's initial. Drawing the letter into the bitmap would need a
      # font the guest does not have in pixel space; the compositor paints it
      # onto the surface afterwards instead.
      def placeholder?(name) = !SPECS.key?(String(name))

      def reset!
        @cache = {}
        self
      end

      # --- Internals ----------------------------------------------------

      # Scale a GRID-space coordinate to +size+. Lengths are scaled from
      # their far edge so a rect never collapses to nothing or spills past
      # the icon: (x + w) maps before w is derived.
      def scale(value, size) = value * size / GRID

      def render(spec, size)
        bitmap = Media::Bitmap.new(size, size, background: spec.fetch(:background))
        spec.fetch(:rects, []).each do |x, y, width, height, color|
          left = scale(x, size)
          top = scale(y, size)
          bitmap.rect(left, top, [scale(x + width, size) - left, 1].max,
                      [scale(y + height, size) - top, 1].max, color:)
        end
        spec.fetch(:lines, []).each do |x0, y0, x1, y1, color|
          bitmap.line(scale(x0, size), scale(y0, size),
                      scale(x1, size), scale(y1, size), color:)
        end
        outline(bitmap, spec.fetch(:border), size)
      end

      def outline(bitmap, color, size)
        thickness = [size / 24, 1].max
        bitmap.rect(0, 0, size, thickness, color:)
        bitmap.rect(0, size - thickness, size, thickness, color:)
        bitmap.rect(0, 0, thickness, size, color:)
        bitmap.rect(size - thickness, 0, thickness, size, color:)
        bitmap
      end

      # Demos, games and live-reloaded applications get a tinted tile chosen
      # from the name, so the same app keeps its colour between boots.
      def placeholder_spec(name)
        { background: DEFAULT_TINTS[name.each_byte.sum % DEFAULT_TINTS.length],
          border: 0x6f6486 }
      end
    end
  end
end
