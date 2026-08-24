# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      module Input
        class KeyState < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({ "Down" => 1, "Up" => 0 })
        end

        class ButtonState < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({ "Released" => 0, "Pressed" => 1 })
        end

        class Keys < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          values = {
            "None" => 0, "Back" => 8, "Tab" => 9, "Enter" => 13, "Pause" => 19,
            "CapsLock" => 20, "Kana" => 21, "Kanji" => 25, "Escape" => 27,
            "ImeConvert" => 28, "ImeNoConvert" => 29, "Space" => 32,
            "PageUp" => 33, "PageDown" => 34, "End" => 35, "Home" => 36,
            "Left" => 37, "Up" => 38, "Right" => 39, "Down" => 40,
            "Select" => 41, "Print" => 42, "Execute" => 43, "PrintScreen" => 44,
            "Insert" => 45, "Delete" => 46, "Help" => 47,
            "LeftWindows" => 91, "RightWindows" => 92, "Apps" => 93, "Sleep" => 95,
            "Multiply" => 106, "Add" => 107, "Separator" => 108, "Subtract" => 109,
            "Decimal" => 110, "Divide" => 111, "NumLock" => 144, "Scroll" => 145,
            "LeftShift" => 160, "RightShift" => 161, "LeftControl" => 162,
            "RightControl" => 163, "LeftAlt" => 164, "RightAlt" => 165,
            "BrowserBack" => 166, "BrowserForward" => 167, "BrowserRefresh" => 168,
            "BrowserStop" => 169, "BrowserSearch" => 170, "BrowserFavorites" => 171,
            "BrowserHome" => 172, "VolumeMute" => 173, "VolumeDown" => 174,
            "VolumeUp" => 175, "MediaNextTrack" => 176, "MediaPreviousTrack" => 177,
            "MediaStop" => 178, "MediaPlayPause" => 179, "LaunchMail" => 180,
            "SelectMedia" => 181, "LaunchApplication1" => 182, "LaunchApplication2" => 183,
            "OemSemicolon" => 186, "OemPlus" => 187, "OemComma" => 188,
            "OemMinus" => 189, "OemPeriod" => 190, "OemQuestion" => 191,
            "OemTilde" => 192, "ChatPadGreen" => 202, "ChatPadOrange" => 203,
            "OemOpenBrackets" => 219, "OemPipe" => 220, "OemCloseBrackets" => 221,
            "OemQuotes" => 222, "Oem8" => 223, "OemBackslash" => 226,
            "ProcessKey" => 229, "OemCopy" => 242, "OemAuto" => 243,
            "OemEnlW" => 244, "Attn" => 246, "Crsel" => 247, "Exsel" => 248,
            "EraseEof" => 249, "Play" => 250, "Zoom" => 251, "Pa1" => 253,
            "OemClear" => 254
          }
          10.times { |index| values["D#{index}"] = 48 + index }
          26.times { |index| values[(65 + index).chr] = 65 + index }
          10.times { |index| values["NumPad#{index}"] = 96 + index }
          24.times { |index| values["F#{index + 1}"] = 112 + index }
          define_values(values)
        end

        class KeyboardState
          include CNA::Runtime::ValueSemantics

          def initialize(keys = [])
            raise TypeError, "KeyboardState.new expects an Array of Keys" unless keys.instance_of?(Array)
            @native = CNA::Native::Layouts::KeyboardState.new
            words = [0, 0, 0, 0]
            keys.each do |key|
              value = Keys.coerce(key).to_i
              words[value / 64] |= 1 << (value % 64)
            end
            words.each_with_index { |word, index| @native.write_u64(8 + index * 8, word) }
          end

          def IsKeyDown(key) = native_bool("cna_keyboard_state_is_key_down", key)
          def IsKeyUp(key) = native_bool("cna_keyboard_state_is_key_up", key)
          def [](key) = self.IsKeyDown(key) ? KeyState::Down : KeyState::Up

          def GetPressedKeys
            count_pointer = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_keyboard_state_get_pressed_key_count", @native.pointer, count_pointer)
            count = count_pointer[0, 4].unpack1("L")
            return [] if count.zero?
            buffer = Fiddle::Pointer.malloc(count * 4, Fiddle::RUBY_FREE)
            output_count = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_keyboard_state_copy_pressed_keys", @native.pointer, buffer, count, output_count)
            buffer[0, count * 4].unpack("L#{count}").map { |value| Keys.coerce(value) }
          end

          def GetHashCode
            words32 = @native.pointer[8, 32].unpack("L8")
            CNA::Runtime::Numeric.wrap_int32(words32.reduce(0, :^))
          end

          def dup = self.class.__send__(:from_native_bytes, @native.pointer[0, @native.class.size])
          def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }

          private

          def value_components = @native.pointer[8, 32].unpack("Q4")

          def native_bool(operation, key)
            value = Keys.coerce(key).to_i
            output = Fiddle::Pointer.malloc(1, Fiddle::RUBY_FREE)
            output[0, 1] = "\0"
            CNA::Native.library.call(operation, @native.pointer, value, output)
            output[0, 1].unpack1("C") != 0
          end

          def self.from_native_bytes(bytes)
            allocate.tap do |value|
              native = CNA::Native::Layouts::KeyboardState.new
              native.pointer[0, native.class.size] = bytes
              value.instance_variable_set(:@native, native)
            end
          end

          class << self
            private :from_native_bytes
          end
        end

        class Keyboard
          class << self
            def new(*) = raise(TypeError, "Keyboard is static")

            def GetState(*arguments)
              game = CNA::Runtime::Context.current_game("Keyboard.GetState")
              host = game.instance_variable_get(:@host)
              raise CNA::InvalidBindingStateError, "Keyboard.GetState requires an initialized CNA Game" unless host && !host.handle.zero?
              native = CNA::Native::Layouts::KeyboardState.new
              if arguments.empty?
                CNA::Native.library.call("cna_keyboard_get_state", host.handle, native.pointer)
              elsif arguments.length == 1
                player = PlayerIndex.coerce(arguments[0])
                CNA::Native.library.call("cna_keyboard_get_state_for_player", host.handle, player.to_i, native.pointer)
              else
                raise ArgumentError, "Keyboard.GetState expects () or (PlayerIndex)"
              end
              KeyboardState.__send__(:from_native_bytes, native.pointer[0, native.class.size])
            end
          end
          private_class_method :new
        end

        class MouseState
          include CNA::Runtime::ValueSemantics

          attr_reader :X, :Y, :LeftButton, :RightButton, :MiddleButton,
                      :XButton1, :XButton2, :ScrollWheelValue

          def initialize(x, y, scroll_wheel, left_button, middle_button, right_button, x_button1, x_button2)
            @X = CNA::Runtime::Numeric.int32(x, "x")
            @Y = CNA::Runtime::Numeric.int32(y, "y")
            @ScrollWheelValue = CNA::Runtime::Numeric.int32(scroll_wheel, "scrollWheel")
            @LeftButton = ButtonState.coerce(left_button)
            @MiddleButton = ButtonState.coerce(middle_button)
            @RightButton = ButtonState.coerce(right_button)
            @XButton1 = ButtonState.coerce(x_button1)
            @XButton2 = ButtonState.coerce(x_button2)
          end

          def Equals(other) = other.instance_of?(MouseState) && self == other
          def !=(other) = !(self == other)

          def GetHashCode
            CNA::Runtime::Numeric.wrap_int32(
              @X ^ @Y ^ @LeftButton.to_i ^ @RightButton.to_i ^ @MiddleButton.to_i ^
                @XButton1.to_i ^ @XButton2.to_i ^ @ScrollWheelValue
            )
          end

          def ToString
            buttons = []
            buttons << "Left" if @LeftButton == ButtonState::Pressed
            buttons << "Right" if @RightButton == ButtonState::Pressed
            buttons << "Middle" if @MiddleButton == ButtonState::Pressed
            buttons << "XButton1" if @XButton1 == ButtonState::Pressed
            buttons << "XButton2" if @XButton2 == ButtonState::Pressed
            "{X:#{@X} Y:#{@Y} Buttons:#{buttons.empty? ? "None" : buttons.join(" ")} Wheel:#{@ScrollWheelValue}}"
          end

          alias hash GetHashCode
          alias to_s ToString

          private

          def value_components
            [@X, @Y, @ScrollWheelValue, @LeftButton, @MiddleButton, @RightButton, @XButton1, @XButton2]
          end

          def self.from_native(native)
            buttons = native.read_u32(24)
            button = lambda do |mask|
              (buttons & mask).zero? ? ButtonState::Released : ButtonState::Pressed
            end
            new(
              native.read_i32(8), native.read_i32(12), native.read_i32(16),
              button.call(CNA::Native::Manifest::CONSTANTS.fetch("CNA_MOUSE_BUTTON_LEFT")),
              button.call(CNA::Native::Manifest::CONSTANTS.fetch("CNA_MOUSE_BUTTON_MIDDLE")),
              button.call(CNA::Native::Manifest::CONSTANTS.fetch("CNA_MOUSE_BUTTON_RIGHT")),
              button.call(CNA::Native::Manifest::CONSTANTS.fetch("CNA_MOUSE_BUTTON_X1")),
              button.call(CNA::Native::Manifest::CONSTANTS.fetch("CNA_MOUSE_BUTTON_X2"))
            )
          end

          class << self
            private :from_native
          end
        end

        class Mouse
          class << self
            def new(*) = raise(TypeError, "Mouse is static")

            def GetState
              host = native_host("Mouse.GetState")
              native = CNA::Native::Layouts::MouseState.new
              CNA::Native.library.call("cna_mouse_get_state", host.handle, native.pointer)
              MouseState.__send__(:from_native, native)
            end

            def SetPosition(x, y)
              native_x = CNA::Runtime::Numeric.int32(x, "x")
              native_y = CNA::Runtime::Numeric.int32(y, "y")
              host = native_host("Mouse.SetPosition")
              CNA::Native.library.call("cna_mouse_set_position", host.handle, native_x, native_y)
              nil
            end

            def WindowHandle
              host = native_host("Mouse.WindowHandle")
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_mouse_get_window_handle", host.handle, output)
              CNA::Runtime::Numeric.intptr_from_uint64_bits(output[0, 8].unpack1("Q"))
            end

            def WindowHandle=(value)
              bits = CNA::Runtime::Numeric.intptr_to_uint64_bits(value, "WindowHandle")
              host = native_host("Mouse.WindowHandle=")
              CNA::Native.library.call("cna_mouse_set_window_handle", host.handle, bits)
              nil
            end

            private

            def native_host(operation)
              game = CNA::Runtime::Context.current_game(operation)
              game.__send__(:assert_owner_thread!)
              host = game.instance_variable_get(:@host)
              unless host && !host.handle.zero?
                raise CNA::InvalidBindingStateError, "#{operation} requires an initialized CNA Game"
              end
              host
            end
          end
          private_class_method :new
        end
      end
    end
  end
end
