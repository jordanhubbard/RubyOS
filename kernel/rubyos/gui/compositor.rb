# frozen_string_literal: true

module RubyOS
  module GUI
    class TranslatedSurface
      def initialize(surface, offset_x, offset_y)
        @surface = surface
        @offset_x = offset_x
        @offset_y = offset_y
      end

      def fill_rect(x, y, width, height, color)
        @surface.fill_rect(x + @offset_x, y + @offset_y, width, height, color)
      end

      def draw_text(x, y, text, **options)
        @surface.draw_text(x + @offset_x, y + @offset_y, text, **options)
      end

      def line(x0, y0, x1, y1, color)
        @surface.line(x0 + @offset_x, y0 + @offset_y,
                      x1 + @offset_x, y1 + @offset_y, color)
      end

      def draw_bitmap(x, y, bitmap, scale: 1)
        @surface.draw_bitmap(x + @offset_x, y + @offset_y, bitmap, scale:)
      end

      def draw_surface(x, y, source, source_rect: nil)
        @surface.draw_surface(x + @offset_x, y + @offset_y, source, source_rect:)
      end
    end

    class Window < Container
      Layout = Data.define(:anchors, :right_gap, :bottom_gap, :minimum_width, :minimum_height)
      TITLE_HEIGHT = 24
      BORDER = 2
      RESIZE_GRIP = 12

      attr_accessor :title, :application
      attr_reader :focused_child
      attr_accessor :focused, :minimized, :resizable
      attr_reader :minimum_width, :minimum_height

      def initialize(title, resizable: true, minimum_width: nil, minimum_height: nil, **options)
        super(**options)
        @title = String(title)
        @focused = false
        @minimized = false
        @resizable = resizable
        @minimum_width = Integer(minimum_width || [width / 2, 140].max)
        @minimum_height = Integer(minimum_height || [height / 2, 80].max)
        @layouts = {}
        @file_drop_handler = nil
        @tick_handler = nil
        @close_handler = nil
      end

      def on_file_drop(&handler)
        @file_drop_handler = handler
        self
      end

      def on_tick(&handler)
        @tick_handler = handler
        self
      end

      def on_close(&handler)
        @close_handler = handler
        self
      end

      def closed
        handler, @close_handler = @close_handler, nil
        handler&.call
        self
      end

      def tick
        @tick_handler&.call
        self
      end

      def draw(surface)
        return unless visible && !minimized
        surface.fill_rect(x + 4, y + 5, width, height, 0x0b0910)
        surface.fill_rect(x, y, width, height, focused ? 0x9b6dff : 0x655b70)
        surface.fill_rect(x + BORDER, y + BORDER, width - BORDER * 2,
                          TITLE_HEIGHT - BORDER, focused ? 0x553184 : 0x393140)
        display_title = title.each_char.first([(width - 72) / 8, 1].max).join
        surface.draw_text(x + 10, y + 7, display_title, color: focused ? 0xffffff : 0xc5bacb)
        surface.fill_rect(x + width - 38, y + 10, 8, 3, focused ? 0xd8cae5 : 0x806774)
        surface.fill_rect(x + width - 18, y + 8, 8, 8, focused ? 0xff668a : 0x806774)
        body_y = y + TITLE_HEIGHT
        surface.fill_rect(x + BORDER, body_y, width - BORDER * 2,
                          height - TITLE_HEIGHT - BORDER, background || 0x201a28)
        translated = TranslatedSurface.new(surface, x + 10, body_y + 9)
        children.each { |child| child.draw(translated) if child.visible }
        draw_resize_grip(surface) if resizable
      end

      def add(child, anchors: [:left, :top], minimum_width: 1, minimum_height: 1)
        result = super(child)
        @layouts[child] = Layout.new(
          anchors: Array(anchors).map(&:to_sym).freeze,
          right_gap: content_width - child.x - child.width,
          bottom_gap: content_height - child.y - child.height,
          minimum_width: Integer(minimum_width), minimum_height: Integer(minimum_height)
        ).freeze
        focus_child(child) if focused_child.nil? && child.focusable?
        result
      end

      def resize_to(new_width, new_height, maximum_width: nil, maximum_height: nil)
        target_width = [Integer(new_width), minimum_width].max
        target_height = [Integer(new_height), minimum_height].max
        target_width = [target_width, Integer(maximum_width)].min if maximum_width
        target_height = [target_height, Integer(maximum_height)].min if maximum_height
        old_content_width = content_width
        old_content_height = content_height
        @width = target_width
        @height = target_height
        relayout(old_content_width, old_content_height)
        invalidate
        self
      end

      def close_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_x >= x + width - 24 && point_y < y + TITLE_HEIGHT
      end

      def minimize_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_x >= x + width - 44 &&
          point_x < x + width - 24 && point_y < y + TITLE_HEIGHT
      end

      def title_hit?(point_x, point_y)
        contains?(point_x, point_y) && point_y < y + TITLE_HEIGHT
      end

      def resize_hit?(point_x, point_y)
        resizable && contains?(point_x, point_y) &&
          point_x >= x + width - RESIZE_GRIP && point_y >= y + height - RESIZE_GRIP
      end

      def handle(event)
        kind = event.fetch("kind", 0)
        if kind == Input::FILE_DROP && @file_drop_handler
          return !!@file_drop_handler.call(event)
        end
        if [Input::POINTER_MOVE, Input::POINTER_UP].include?(kind) &&
           focused_child&.enabled && focused_child.pointer_capture? &&
           focused_child.respond_to?(:handle_pointer)
          local_x = event.fetch("x") - x - 10
          local_y = event.fetch("y") - y - TITLE_HEIGHT - 9
          return focused_child.handle_pointer(local_x, local_y, event)
        end
        if kind == Input::POINTER_DOWN && event.fetch("button", 0) == 1
          local_x = event.fetch("x") - x - 10
          local_y = event.fetch("y") - y - TITLE_HEIGHT - 9
          child = children.reverse.find { |candidate| candidate.contains?(local_x, local_y) }
          if child&.enabled
            focus_child(child) if child.focusable?
            return child.handle_pointer(local_x, local_y, event) if child.respond_to?(:handle_pointer)
            return child.handle(:click) if child.is_a?(Button)
          end
        end
        if kind == Input::KEY_DOWN && event.fetch("code", 0) == 9
          cycle_focus
          return true
        end
        if kind == Input::POINTER_WHEEL
          local_x = event.fetch("x", 0) - x - 10
          local_y = event.fetch("y", 0) - y - TITLE_HEIGHT - 9
          child = children.reverse.find { |candidate| candidate.contains?(local_x, local_y) }
          focus_child(child) if child&.focusable?
          return true if child&.enabled && child.handle(event)
        end
        return true if focused_child&.enabled && focused_child.handle(event)
        false
      end

      def context_menu_items(point_x, point_y)
        local_x = point_x - x - 10
        local_y = point_y - y - TITLE_HEIGHT - 9
        child = children.reverse.find { |candidate| candidate.contains?(local_x, local_y) }
        return [] unless child&.enabled && child.respond_to?(:context_menu_items)

        focus_child(child) if child.focusable?
        Array(child.context_menu_items)
      end

      def focus_child(child)
        return unless child&.focusable? && children.include?(child)

        children.each { |candidate| candidate.focused = false }
        @focused_child = child
        child.focused = true
        invalidate
        child
      end

      private

      def content_width = [width - 20, 1].max
      def content_height = [height - TITLE_HEIGHT - 18, 1].max

      def relayout(_old_width, _old_height)
        children.each do |child|
          layout = @layouts.fetch(child)
          anchors = layout.anchors
          if anchors.include?(:left) && anchors.include?(:right)
            child.width = [content_width - child.x - layout.right_gap, layout.minimum_width].max
          elsif anchors.include?(:right) && !anchors.include?(:left)
            child.x = content_width - layout.right_gap - child.width
          end
          if anchors.include?(:top) && anchors.include?(:bottom)
            child.height = [content_height - child.y - layout.bottom_gap, layout.minimum_height].max
          elsif anchors.include?(:bottom) && !anchors.include?(:top)
            child.y = content_height - layout.bottom_gap - child.height
          end
        end
      end

      def draw_resize_grip(surface)
        color = focused ? 0xb792ff : 0x806774
        3.times do |index|
          size = 3 + index * 3
          surface.fill_rect(x + width - size, y + height - 2, size, 2, color)
        end
      end

      def cycle_focus
        candidates = children.select { |child| child.visible && child.enabled && child.focusable? }
        return if candidates.empty?

        index = focused_child ? candidates.index(focused_child) : nil
        focus_child(candidates.fetch(index ? (index + 1) % candidates.length : 0))
      end
    end

    class Compositor
      Binding = Data.define(:name, :code, :mods, :action)
      DockItem = Data.define(:name, :label, :application, :action)
      MENU_HEIGHT = 24
      DOCK_HEIGHT = 42

      attr_reader :width, :height, :windows, :file_transfer

      def initialize(width:, height:, title: "RubyOS")
        @width = width
        @height = height
        @title = title
        @windows = []
        @dock_items = []
        @pinned_dock_items = {}
        @dock_change = nil
        @shortcuts = []
        @dragging = nil
        @resizing = nil
        @system_menus = []
        @menu_bar = MenuBar.new(width:, height:)
        @context_menu = ContextMenu.new(width:, height:, bottom_margin: DOCK_HEIGHT)
        @desktop_context_items = []
        @keybindings = {}
        @bindings_by_name = {}
        @key_capture = nil
        @file_transfer = nil
        @file_drop_handler = nil
      end

      def install_file_transfer(service, &fallback)
        @file_transfer = service
        @file_drop_handler = fallback
        self
      end

      def add_window(window)
        windows << window
        focus(window)
        window
      end

      def close(window)
        return unless window
        return unless windows.include?(window)

        window.closed
        windows.delete(window)
        focus(windows.last) if windows.any?
        refresh_menus
        window
      end

      def minimize(window)
        return unless window && windows.include?(window)

        window.minimized = true
        focus(windows.reverse.find { |candidate| !candidate.minimized })
        refresh_menus
        window
      end

      def focus(window)
        return unless windows.include?(window)
        windows.each { |candidate| candidate.focused = false }
        windows.delete(window)
        windows << window
        window.focused = true
        refresh_menus
        window
      end

      def focused_window
        windows.reverse.find { |window| !window.minimized }
      end

      def window_at(point_x, point_y)
        windows.reverse.find do |window|
          window.visible && !window.minimized && window.contains?(point_x, point_y)
        end
      end

      def add_dock_item(label, &action)
        register_dock_item("legacy-#{@dock_items.length}-#{label}", label,
                           pinned: true, &action)
      end

      def register_dock_item(name, label, application: nil, pinned: false, &action)
        raise ArgumentError, "dock action required" unless action

        name = String(name)
        @dock_items.reject! { |item| item.name == name }
        @dock_items << DockItem.new(name:, label: String(label), application:, action:).freeze
        @pinned_dock_items[name] = true if pinned
        self
      end

      def on_dock_change(&callback)
        @dock_change = callback
        self
      end

      def pin_dock_item(name)
        name = String(name)
        raise KeyError, "dock item not found: #{name}" unless @dock_items.any? { |item| item.name == name }
        return false if @pinned_dock_items[name]

        @pinned_dock_items[name] = true
        persist_dock
        true
      end

      def unpin_dock_item(name)
        changed = !!@pinned_dock_items.delete(String(name))
        persist_dock if changed
        changed
      end

      def pinned_dock_names
        @dock_items.filter_map { |item| item.name if @pinned_dock_items[item.name] }
      end

      def visible_dock_labels = visible_dock_items.map(&:label)

      def dock_item_center(label)
        index = visible_dock_items.index { |item| item.label == String(label) }
        raise KeyError, "dock item not found: #{label}" unless index

        x = 12 + index * dock_slot_width
        [x + (dock_slot_width - 8) / 2, height - DOCK_HEIGHT + 20]
      end

      def dock_item_center_by_name(name)
        index = visible_dock_items.index { |item| item.name == String(name) }
        raise KeyError, "dock item not found: #{name}" unless index

        x = 12 + index * dock_slot_width
        [x + (dock_slot_width - 8) / 2, height - DOCK_HEIGHT + 20]
      end

      def add_shortcut(label, x:, y:, &action)
        @shortcuts << [String(label), Integer(x), Integer(y), action]
        self
      end

      def set_system_menus(menus)
        @system_menus = Array(menus)
        refresh_menus
        self
      end

      def menus = @menu_bar.menus

      def set_desktop_context_menu(items)
        @desktop_context_items = Array(items)
        self
      end

      def context_menu_open? = @context_menu.open?
      def context_item_center(index) = @context_menu.item_center(index)

      def bind_key(code, mods: 0, name: nil, &action)
        raise ArgumentError, "key binding action required" unless action

        code = Integer(code)
        mods = Integer(mods) & ~Input::MOD_CAPS
        name = String(name || "Key #{code}")
        if (previous = @bindings_by_name[name])
          @keybindings.delete([previous.code, previous.mods])
        end
        binding = Binding.new(name:, code:, mods:, action:).freeze
        @keybindings[[code, mods]] = binding
        @bindings_by_name[name] = binding
        self
      end

      def keybindings = @bindings_by_name.values

      def rebind_key(name, code:, mods: 0)
        previous = @bindings_by_name.fetch(String(name))
        bind_key(code, mods:, name: previous.name, &previous.action)
      end

      def capture_next_key(&callback)
        raise ArgumentError, "key capture callback required" unless callback

        @key_capture = callback
        self
      end

      def handle(event)
        kind = event.fetch("kind", 0)
        if kind == Input::FILE_DROP
          window = window_at(event.fetch("x", 0), event.fetch("y", 0)) || focused_window
          focus(window) if window
          return true if window&.handle(event)

          return !!@file_drop_handler&.call(event)
        end
        return true if @context_menu.handle(event)
        return true if @menu_bar.handle(event)
        if kind == Input::KEY_DOWN
          if @key_capture
            callback = @key_capture
            @key_capture = nil
            callback.call(event)
            return true
          end
          chord = [event.fetch("code", 0), event.fetch("mods", 0) & ~Input::MOD_CAPS]
          if (binding = @keybindings[chord])
            binding.action.call
            return true
          end
        end
        return focused_window&.handle(event) || false if kind == 1 || kind == 2
        if kind == Input::POINTER_WHEEL
          window = window_at(event.fetch("x", 0), event.fetch("y", 0))
          return window&.handle(event) || false
        end
        if kind == Input::POINTER_DOWN && event.fetch("button", 0) == 3
          return open_context_menu(event.fetch("x"), event.fetch("y"))
        end
        if kind == Input::POINTER_MOVE && @resizing
          window, start_x, start_y, start_width, start_height = @resizing
          window.resize_to(
            start_width + event.fetch("x") - start_x,
            start_height + event.fetch("y") - start_y,
            maximum_width: width - window.x,
            maximum_height: height - DOCK_HEIGHT - window.y
          )
          return true
        end
        if kind == Input::POINTER_MOVE && @dragging
          window, offset_x, offset_y = @dragging
          window.x = [[event.fetch("x") - offset_x, 0].max, width - window.width].min
          maximum_y = [height - DOCK_HEIGHT - window.height, MENU_HEIGHT].max
          window.y = [[event.fetch("y") - offset_y, MENU_HEIGHT].max,
                      maximum_y].min
          return true
        end
        if kind == Input::POINTER_UP && @resizing
          @resizing = nil
          return true
        end
        if kind == Input::POINTER_UP && @dragging
          @dragging = nil
          return true
        end
        if [Input::POINTER_MOVE, Input::POINTER_UP].include?(kind)
          return focused_window&.handle(event) || false
        end
        return false unless kind == 4 && event.fetch("button", 0) == 1
        point_x = event.fetch("x")
        point_y = event.fetch("y")
        if point_y >= height - DOCK_HEIGHT
          item = dock_item_at(point_x, point_y)
          activate_dock_item(item) if item
          return !item.nil?
        end
        window = window_at(point_x, point_y)
        unless window
          shortcut = @shortcuts.find do |_label, x, y, _action|
            x <= point_x && point_x < x + 48 && y <= point_y && point_y < y + 48
          end
          shortcut&.last&.call
          return !shortcut.nil?
        end
        if window.close_hit?(point_x, point_y)
          close(window)
        elsif window.minimize_hit?(point_x, point_y)
          minimize(window)
        elsif window.resize_hit?(point_x, point_y)
          focus(window)
          @resizing = [window, point_x, point_y, window.width, window.height]
        else
          focus(window)
          @dragging = [window, point_x - window.x, point_y - window.y] if window.title_hit?(point_x, point_y)
          window.handle(event)
        end
        true
      end

      def draw(surface, uptime: nil)
        surface.fill_rect(0, 0, width, height, 0x171321)
        draw_wallpaper(surface)
        windows.each do |window|
          window.tick unless window.minimized
          window.draw(surface)
        end
        draw_dock(surface)
        @menu_bar.draw(surface, active_title: focused_window&.title,
                       status: uptime || "Ruby 4")
        @context_menu.draw(surface)
        self
      end

      private

      def open_context_menu(point_x, point_y)
        @menu_bar.dismiss
        if (dock_item = dock_item_at(point_x, point_y))
          return @context_menu.show(point_x, point_y, dock_context_items(dock_item))
        end
        window = window_at(point_x, point_y)
        items = if window
                  focus(window)
                  window.context_menu_items(point_x, point_y).then do |child_items|
                    child_items.empty? ? window_context_items(window) : child_items
                  end
                else
                  @desktop_context_items
                end
        @context_menu.show(point_x, point_y, items)
      end

      def window_context_items(window)
        [
          MenuItem.command("Minimize") { minimize(window) },
          MenuItem.command("Close", shortcut: "Ctrl+W") { close(window) }
        ]
      end

      def dock_context_items(item)
        pin_action = if @pinned_dock_items[item.name]
                       MenuItem.command("Remove from Dock") { unpin_dock_item(item.name) }
                     else
                       MenuItem.command("Keep in Dock") { pin_dock_item(item.name) }
                     end
        [
          MenuItem.command("Open #{item.name}") { activate_dock_item(item) },
          MenuItem.separator,
          pin_action
        ]
      end

      def refresh_menus
        application_menus = focused_window&.application&.menus(self) || []
        @menu_bar.replace(@system_menus + application_menus)
      end

      def draw_wallpaper(surface)
        surface.fill_rect(0, MENU_HEIGHT, width, height - MENU_HEIGHT, 0x191624)
        MENU_HEIGHT.step(height - DOCK_HEIGHT, 48) do |row|
          surface.fill_rect(0, row, width, 1, 0x211c30)
        end
        0.step(width - 1, 48) { |column| surface.fill_rect(column, MENU_HEIGHT, 1, height, 0x1e1a2b) }
        @shortcuts.each do |label, x, y, _action|
          surface.fill_rect(x + 8, y, 28, 28, 0x553184)
          surface.draw_text(x, y + 34, label, color: 0xe8dff5)
        end
      end

      def draw_dock(surface)
        y = height - DOCK_HEIGHT
        surface.fill_rect(0, y, width, DOCK_HEIGHT, 0x17131d)
        surface.fill_rect(0, y, width, 2, 0x49325f)
        visible_dock_items.each_with_index do |item, index|
          x = 12 + index * dock_slot_width
          active = item.application && windows.any? do |window|
            window.application.equal?(item.application)
          end
          surface.fill_rect(x, y + 6, dock_slot_width - 8, 28,
                            active ? 0x7048a8 : 0x49325f)
          columns = [[(dock_slot_width - 14) / 8, 1].max, item.label.each_char.count].min
          surface.draw_text(x + 7, y + 14, item.label.each_char.first(columns).join,
                            color: 0xf2eaf7)
          surface.fill_rect(x + 5, y + 35, dock_slot_width - 14, 2, 0xb792ff) if active
        end
      end

      def visible_dock_items
        @dock_items.select do |item|
          @pinned_dock_items[item.name] ||
            (item.application && windows.any? { |window| window.application.equal?(item.application) })
        end
      end

      def dock_item_at(point_x, point_y)
        return nil unless point_y >= height - DOCK_HEIGHT && point_x >= 12

        index = (point_x - 12) / dock_slot_width
        visible_dock_items[index] if index >= 0
      end

      def activate_dock_item(item)
        existing = item.application && windows.reverse.find do |window|
          window.application.equal?(item.application)
        end
        if existing
          existing.minimized = false
          focus(existing)
        else
          item.action.call
        end
      end

      def persist_dock
        @dock_change&.call(pinned_dock_names)
      end

      def dock_slot_width
        [[(@width - 24) / [visible_dock_items.length, 1].max, 32].max, 96].min
      end
    end
  end
end
