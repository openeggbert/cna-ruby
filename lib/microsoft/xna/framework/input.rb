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
      end
    end
  end
end
