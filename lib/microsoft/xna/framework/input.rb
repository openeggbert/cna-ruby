# frozen_string_literal: true

require_relative "../framework"
require_relative "input/touch"

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

        class Buttons < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "DPadUp" => 1, "DPadDown" => 2, "DPadLeft" => 4, "DPadRight" => 8,
            "Start" => 16, "Back" => 32, "LeftStick" => 64, "RightStick" => 128,
            "LeftShoulder" => 256, "RightShoulder" => 512, "BigButton" => 2_048,
            "A" => 4_096, "B" => 8_192, "X" => 16_384, "Y" => 32_768,
            "RightThumbstickUp" => 16_777_216,
            "RightThumbstickDown" => 33_554_432,
            "RightThumbstickRight" => 67_108_864,
            "RightThumbstickLeft" => 134_217_728,
            "LeftThumbstickUp" => 268_435_456,
            "LeftThumbstickDown" => 536_870_912,
            "LeftThumbstickRight" => 1_073_741_824,
            "LeftThumbstickLeft" => 2_097_152,
            "RightTrigger" => 4_194_304,
            "LeftTrigger" => 8_388_608
          }, flags: true)
        end

        class GamePadDeadZone < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({ "None" => 0, "IndependentAxes" => 1, "Circular" => 2 })
        end

        class GamePadType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Unknown" => 0, "GamePad" => 1, "Wheel" => 2, "ArcadeStick" => 3,
            "FlightStick" => 4, "DancePad" => 5, "Guitar" => 6,
            "AlternateGuitar" => 7, "DrumKit" => 8, "BigButtonPad" => 768
          })
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

        class GamePadButtons
          include CNA::Runtime::ValueSemantics

          PROPERTY_BITS = {
            A: Buttons::A, B: Buttons::B, Back: Buttons::Back, X: Buttons::X,
            Y: Buttons::Y, Start: Buttons::Start, LeftShoulder: Buttons::LeftShoulder,
            LeftStick: Buttons::LeftStick, RightShoulder: Buttons::RightShoulder,
            RightStick: Buttons::RightStick, BigButton: Buttons::BigButton
          }.freeze
          private_constant :PROPERTY_BITS

          def initialize(buttons)
            @mask = Buttons.coerce(buttons).to_i & 0x0000_fbf0
          end

          PROPERTY_BITS.each do |property, button|
            define_method(property) do
              (@mask & button.to_i).zero? ? ButtonState::Released : ButtonState::Pressed
            end
          end

          def GetHashCode
            hash = PROPERTY_BITS.keys.reduce(0) { |value, property| value ^ public_send(property).to_i }
            hash.zero? ? 2_147_483_647 : hash
          end

          def ToString
            labels = %i[A B X Y LeftShoulder RightShoulder LeftStick RightStick Start Back BigButton]
                     .select { |property| public_send(property) == ButtonState::Pressed }
            "{Buttons:#{labels.empty? ? "None" : labels.join(" ")}}"
          end

          alias to_s ToString

          private

          def value_components = [Buttons.coerce(@mask)]
          def physical_mask = @mask
        end

        class GamePadDPad
          include CNA::Runtime::ValueSemantics

          PROPERTY_BITS = {
            Up: Buttons::DPadUp, Down: Buttons::DPadDown,
            Right: Buttons::DPadRight, Left: Buttons::DPadLeft
          }.freeze
          private_constant :PROPERTY_BITS

          def initialize(up_value, down_value, left_value, right_value)
            @Up = ButtonState.coerce(up_value)
            @Down = ButtonState.coerce(down_value)
            @Left = ButtonState.coerce(left_value)
            @Right = ButtonState.coerce(right_value)
          end

          attr_reader :Up, :Down, :Right, :Left

          def GetHashCode
            hash = @Up.to_i ^ @Right.to_i ^ @Down.to_i ^ @Left.to_i
            hash.zero? ? 2_147_483_647 : hash
          end

          def ToString
            labels = %i[Up Down Left Right]
                     .select { |property| public_send(property) == ButtonState::Pressed }
            "{DPad:#{labels.empty? ? "None" : labels.join(" ")}}"
          end

          alias to_s ToString

          private

          def value_components = [@Up, @Down, @Left, @Right]
          def physical_mask
            PROPERTY_BITS.reduce(0) do |mask, (property, button)|
              public_send(property) == ButtonState::Pressed ? mask | button.to_i : mask
            end
          end

          def self.from_mask(mask)
            pressed = lambda { |bit| (mask & bit.to_i).zero? ? ButtonState::Released : ButtonState::Pressed }
            new(pressed.call(Buttons::DPadUp), pressed.call(Buttons::DPadDown),
                pressed.call(Buttons::DPadLeft), pressed.call(Buttons::DPadRight))
          end

          class << self
            private :from_mask
          end
        end

        class GamePadTriggers
          include CNA::Runtime::ValueSemantics

          def initialize(left_trigger, right_trigger)
            @Left = clamp_trigger(left_trigger)
            @Right = clamp_trigger(right_trigger)
          end

          attr_reader :Left, :Right

          def GetHashCode
            hash = CNA::Runtime::Numeric.f32_bits(@Left) ^ CNA::Runtime::Numeric.f32_bits(@Right)
            hash.zero? ? 2_147_483_647 : CNA::Runtime::Numeric.wrap_int32(hash)
          end

          def ToString
            numeric = CNA::Runtime::Numeric
            "{Left:#{numeric.single_string(@Left)} Right:#{numeric.single_string(@Right)}}"
          end

          alias to_s ToString

          private

          def value_components = [@Left, @Right]
          def clamp_trigger(value)
            number = CNA::Runtime::Numeric.f32(value)
            return number if number.nan?
            return 1.0 if number > 1.0
            return 0.0 if number <= 0.0

            number
          end
        end

        class GamePadThumbSticks
          include CNA::Runtime::ValueSemantics

          def initialize(left_thumbstick, right_thumbstick)
            raise TypeError, "leftThumbstick must be Vector2" unless left_thumbstick.instance_of?(Vector2)
            raise TypeError, "rightThumbstick must be Vector2" unless right_thumbstick.instance_of?(Vector2)

            @Left = clamp_vector(left_thumbstick)
            @Right = clamp_vector(right_thumbstick)
          end

          def Left = @Left.dup
          def Right = @Right.dup

          def GetHashCode
            hash = [@Left.X, @Left.Y, @Right.X, @Right.Y].reduce(0) do |value, component|
              value ^ CNA::Runtime::Numeric.f32_bits(component)
            end
            hash.zero? ? 2_147_483_647 : CNA::Runtime::Numeric.wrap_int32(hash)
          end

          def ToString = "{Left:#{@Left.ToString} Right:#{@Right.ToString}}"
          alias to_s ToString

          private

          def value_components = [@Left, @Right]
          def clamp_vector(vector)
            Vector2.Max(Vector2.Min(vector, Vector2.One), Vector2.new(-1.0))
          end
        end

        class GamePadCapabilities
          PROPERTIES = %i[
            GamePadType IsConnected HasAButton HasBackButton HasBButton
            HasDPadDownButton HasDPadLeftButton HasDPadRightButton HasDPadUpButton
            HasLeftShoulderButton HasLeftStickButton HasRightShoulderButton HasRightStickButton
            HasStartButton HasXButton HasYButton HasBigButton HasLeftXThumbStick
            HasLeftYThumbStick HasRightXThumbStick HasRightYThumbStick HasLeftTrigger
            HasRightTrigger HasLeftVibrationMotor HasRightVibrationMotor HasVoiceSupport
          ].freeze
          private_constant :PROPERTIES

          attr_reader(*PROPERTIES)

          def dup = self.class.__send__(:from_values, PROPERTIES.to_h { |name| [name, public_send(name)] })
          def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }

          private

          def initialize = initialize_values({})
          def initialize_values(values)
            PROPERTIES.each do |name|
              default = name == :GamePadType ? Input::GamePadType::Unknown : false
              instance_variable_set(:"@#{name}", values.fetch(name, default))
            end
          end

          def self.from_values(values)
            allocate.tap { |capabilities| capabilities.__send__(:initialize_values, values) }
          end

          def self.from_native(native)
            native_types = {
              0 => Input::GamePadType::Unknown, 1 => Input::GamePadType::GamePad,
              2 => Input::GamePadType::Wheel, 3 => Input::GamePadType::ArcadeStick,
              4 => Input::GamePadType::FlightStick, 5 => Input::GamePadType::DancePad,
              6 => Input::GamePadType::Guitar, 7 => Input::GamePadType::AlternateGuitar,
              8 => Input::GamePadType::DrumKit, 9 => Input::GamePadType::BigButtonPad
            }
            values = {
              GamePadType: native_types.fetch(native.read_u32(8), Input::GamePadType::Unknown),
              IsConnected: native.read_u8(12) != 0,
              HasAButton: native.read_u8(13) != 0, HasBButton: native.read_u8(14) != 0,
              HasXButton: native.read_u8(15) != 0, HasYButton: native.read_u8(16) != 0,
              HasBackButton: native.read_u8(17) != 0, HasStartButton: native.read_u8(18) != 0,
              HasBigButton: native.read_u8(19) != 0, HasDPadUpButton: native.read_u8(20) != 0,
              HasDPadDownButton: native.read_u8(21) != 0, HasDPadLeftButton: native.read_u8(22) != 0,
              HasDPadRightButton: native.read_u8(23) != 0,
              HasLeftShoulderButton: native.read_u8(24) != 0,
              HasRightShoulderButton: native.read_u8(25) != 0,
              HasLeftStickButton: native.read_u8(26) != 0,
              HasRightStickButton: native.read_u8(27) != 0,
              HasLeftXThumbStick: native.read_u8(28) != 0,
              HasLeftYThumbStick: native.read_u8(29) != 0,
              HasRightXThumbStick: native.read_u8(30) != 0,
              HasRightYThumbStick: native.read_u8(31) != 0,
              HasLeftTrigger: native.read_u8(32) != 0, HasRightTrigger: native.read_u8(33) != 0,
              HasLeftVibrationMotor: native.read_u8(34) != 0,
              HasRightVibrationMotor: native.read_u8(35) != 0,
              HasVoiceSupport: native.read_u8(36) != 0
            }
            from_values(values)
          end

          class << self
            private :new, :allocate, :from_values, :from_native
          end
        end

        class GamePadState
          include CNA::Runtime::ValueSemantics

          KNOWN_BUTTON_MASK = 0x7fe0_fbff
          private_constant :KNOWN_BUTTON_MASK

          def initialize(*arguments)
            case arguments.length
            when 4
              initialize_components(*arguments, connected: true, packet_number: 0)
            when 5
              initialize_values(*arguments)
            else
              raise ArgumentError, "GamePadState.new expects (thumbSticks, triggers, buttons, dPad) or (leftThumbStick, rightThumbStick, leftTrigger, rightTrigger, buttons)"
            end
          end

          attr_reader :IsConnected, :PacketNumber
          def Buttons = @Buttons.dup
          def DPad = @DPad.dup
          def ThumbSticks = @ThumbSticks.dup
          def Triggers = @Triggers.dup

          def IsButtonDown(button)
            value = Input::Buttons.coerce(button).to_i
            (value & @query_buttons) == value
          end
          def IsButtonUp(button) = !IsButtonDown(button)

          def GetHashCode
            CNA::Runtime::Numeric.wrap_int32(
              @ThumbSticks.GetHashCode ^ @Triggers.GetHashCode ^ @Buttons.GetHashCode ^
                (@IsConnected ? 1 : 0) ^ @DPad.GetHashCode ^ @PacketNumber
            )
          end

          def ToString = "{IsConnected:#{@IsConnected ? "True" : "False"}}"
          alias to_s ToString

          def dup
            self.class.__send__(:from_components, @ThumbSticks, @Triggers, @Buttons, @DPad,
                                @IsConnected, @PacketNumber, @query_buttons)
          end

          def clone(freeze: true) = dup.tap { |value| value.freeze if freeze && frozen? }

          private

          def value_components = [@IsConnected, @PacketNumber, @ThumbSticks, @Triggers, @Buttons, @DPad]

          def initialize_values(left_stick, right_stick, left_trigger, right_trigger, buttons)
            raise TypeError, "leftThumbStick must be Vector2" unless left_stick.instance_of?(Vector2)
            raise TypeError, "rightThumbStick must be Vector2" unless right_stick.instance_of?(Vector2)
            unless buttons.nil? || buttons.instance_of?(Array)
              raise TypeError, "buttons must be an Array of Buttons or nil"
            end

            mask = (buttons || []).reduce(0) { |value, button| value | Input::Buttons.coerce(button).to_i }
            gamepad_buttons = GamePadButtons.new(Input::Buttons.coerce(mask & KNOWN_BUTTON_MASK))
            dpad = GamePadDPad.__send__(:from_mask, mask)
            initialize_components(GamePadThumbSticks.new(left_stick, right_stick),
                                  GamePadTriggers.new(left_trigger, right_trigger),
                                  gamepad_buttons, dpad, connected: true, packet_number: 0)
          end

          def initialize_components(thumb_sticks, triggers, buttons, dpad, connected:, packet_number:,
                                    query_buttons: nil)
            raise TypeError, "thumbSticks must be GamePadThumbSticks" unless thumb_sticks.instance_of?(GamePadThumbSticks)
            raise TypeError, "triggers must be GamePadTriggers" unless triggers.instance_of?(GamePadTriggers)
            raise TypeError, "buttons must be GamePadButtons" unless buttons.instance_of?(GamePadButtons)
            raise TypeError, "dPad must be GamePadDPad" unless dpad.instance_of?(GamePadDPad)

            @ThumbSticks = thumb_sticks.dup
            @Triggers = triggers.dup
            @Buttons = buttons.dup
            @DPad = dpad.dup
            @IsConnected = connected == true
            @PacketNumber = CNA::Runtime::Numeric.int32(packet_number, "packetNumber")
            @query_buttons = query_buttons || derive_query_buttons
          end

          def derive_query_buttons
            mask = @Buttons.__send__(:physical_mask) | @DPad.__send__(:physical_mask)
            left = @ThumbSticks.Left
            right = @ThumbSticks.Right
            left_x = internal_stick_axis(left.X)
            left_y = internal_stick_axis(left.Y)
            right_x = internal_stick_axis(right.X)
            right_y = internal_stick_axis(right.Y)
            left_value = internal_trigger(@Triggers.Left)
            right_value = internal_trigger(@Triggers.Right)
            mask |= Input::Buttons::LeftThumbstickLeft.to_i if left_x < -7_849
            mask |= Input::Buttons::LeftThumbstickRight.to_i if left_x > 7_849
            mask |= Input::Buttons::LeftThumbstickDown.to_i if left_y < -7_849
            mask |= Input::Buttons::LeftThumbstickUp.to_i if left_y > 7_849
            mask |= Input::Buttons::RightThumbstickLeft.to_i if right_x < -8_689
            mask |= Input::Buttons::RightThumbstickRight.to_i if right_x > 8_689
            mask |= Input::Buttons::RightThumbstickDown.to_i if right_y < -8_689
            mask |= Input::Buttons::RightThumbstickUp.to_i if right_y > 8_689
            mask |= Input::Buttons::LeftTrigger.to_i if left_value > 30
            mask |= Input::Buttons::RightTrigger.to_i if right_value > 30
            mask
          end

          def derive_native_query_buttons(dead_zone, physical_mask)
            mask = physical_mask
            left = @ThumbSticks.Left
            right = @ThumbSticks.Right
            if dead_zone == GamePadDeadZone::Circular
              left = circular_raw_vector(left, 7_849.0 / 32_768.0)
              right = circular_raw_vector(right, 8_689.0 / 32_768.0)
              left_x = internal_stick_axis(left.X)
              left_y = internal_stick_axis(left.Y)
              right_x = internal_stick_axis(right.X)
              right_y = internal_stick_axis(right.Y)
              mask |= Input::Buttons::LeftThumbstickLeft.to_i if left_x < -7_849
              mask |= Input::Buttons::LeftThumbstickRight.to_i if left_x > 7_849
              mask |= Input::Buttons::LeftThumbstickDown.to_i if left_y < -7_849
              mask |= Input::Buttons::LeftThumbstickUp.to_i if left_y > 7_849
              mask |= Input::Buttons::RightThumbstickLeft.to_i if right_x < -8_689
              mask |= Input::Buttons::RightThumbstickRight.to_i if right_x > 8_689
              mask |= Input::Buttons::RightThumbstickDown.to_i if right_y < -8_689
              mask |= Input::Buttons::RightThumbstickUp.to_i if right_y > 8_689
            elsif dead_zone == GamePadDeadZone::IndependentAxes
              mask |= Input::Buttons::LeftThumbstickLeft.to_i if left.X < 0.0
              mask |= Input::Buttons::LeftThumbstickRight.to_i if left.X > 0.0
              mask |= Input::Buttons::LeftThumbstickDown.to_i if left.Y < 0.0
              mask |= Input::Buttons::LeftThumbstickUp.to_i if left.Y > 0.0
              mask |= Input::Buttons::RightThumbstickLeft.to_i if right.X < 0.0
              mask |= Input::Buttons::RightThumbstickRight.to_i if right.X > 0.0
              mask |= Input::Buttons::RightThumbstickDown.to_i if right.Y < 0.0
              mask |= Input::Buttons::RightThumbstickUp.to_i if right.Y > 0.0
            else
              mask = derive_query_buttons
            end
            mask |= Input::Buttons::LeftTrigger.to_i if @Triggers.Left > 0.0 && dead_zone != GamePadDeadZone::None
            mask |= Input::Buttons::RightTrigger.to_i if @Triggers.Right > 0.0 && dead_zone != GamePadDeadZone::None
            mask
          end

          def circular_raw_vector(value, dead_zone)
            numeric = CNA::Runtime::Numeric
            magnitude = numeric.sqrt32(numeric.add32(numeric.mul32(value.X, value.X),
                                                       numeric.mul32(value.Y, value.Y)))
            return Vector2.Zero if magnitude.zero?

            zone = numeric.f32(dead_zone)
            raw_magnitude = numeric.add32(numeric.mul32(magnitude, numeric.sub32(1.0, zone)), zone)
            factor = numeric.div32(raw_magnitude, magnitude)
            Vector2.new(numeric.mul32(value.X, factor), numeric.mul32(value.Y, factor))
          end

          def internal_stick_axis(value)
            converted = CNA::Runtime::Numeric.mul32(value, 32_767.0)
            converted.finite? ? converted.truncate : 0
          end

          def internal_trigger(value)
            converted = CNA::Runtime::Numeric.mul32(value, 255.0)
            converted.finite? ? converted.truncate & 0xff : 0
          end

          def self.from_components(thumb_sticks, triggers, buttons, dpad, connected, packet, query)
            allocate.tap do |state|
              state.__send__(:initialize_components, thumb_sticks, triggers, buttons, dpad,
                             connected: connected, packet_number: packet, query_buttons: query)
            end
          end

          def self.from_native(native, dead_zone = GamePadDeadZone::IndependentAxes)
            thumb_sticks = GamePadThumbSticks.new(
              Vector2.new(native.read_f32(24), native.read_f32(28)),
              Vector2.new(native.read_f32(32), native.read_f32(36))
            )
            triggers = GamePadTriggers.new(native.read_f32(40), native.read_f32(44))
            native_mask = native.read_u32(16) & KNOWN_BUTTON_MASK
            physical_mask = native_mask & 0x0000_fbff
            buttons = GamePadButtons.new(Input::Buttons.coerce(physical_mask))
            dpad = GamePadDPad.__send__(:from_mask, physical_mask)
            state = from_components(thumb_sticks, triggers, buttons, dpad, native.read_u8(8) != 0,
                                    native.read_i32(12), physical_mask)
            state.instance_variable_set(:@query_buttons,
                                        state.__send__(:derive_native_query_buttons, dead_zone, physical_mask))
            state
          end

          class << self
            private :from_components, :from_native
          end
        end

        class GamePad
          class << self
            def new(*) = raise(TypeError, "GamePad is static")

            def GetState(*arguments)
              unless (1..2).cover?(arguments.length)
                raise ArgumentError, "GamePad.GetState expects (PlayerIndex) or (PlayerIndex, GamePadDeadZone)"
              end
              player = native_player(arguments[0])
              dead_zone_mode = GamePadDeadZone.coerce(arguments[1]) if arguments.length == 2
              dead_zone = native_dead_zone(dead_zone_mode) if arguments.length == 2
              native = CNA::Native::Layouts::GamePadState.new
              host = CNA::Runtime::Context.native_host("GamePad.GetState")
              if arguments.length == 1
                CNA::Native.library.call("cna_gamepad_get_state", host.handle, player, native.pointer)
              else
                CNA::Native.library.call("cna_gamepad_get_state_with_dead_zone", host.handle,
                                         player, dead_zone, native.pointer)
              end
              mode = arguments.length == 1 ? GamePadDeadZone::IndependentAxes : dead_zone_mode
              GamePadState.__send__(:from_native, native, mode)
            end

            def GetCapabilities(player_index)
              player = native_player(player_index)
              native = CNA::Native::Layouts::GamePadCapabilities.new
              host = CNA::Runtime::Context.native_host("GamePad.GetCapabilities")
              CNA::Native.library.call("cna_gamepad_get_capabilities", host.handle, player, native.pointer)
              GamePadCapabilities.__send__(:from_native, native)
            end

            def SetVibration(player_index, left_motor, right_motor)
              player = native_player(player_index)
              left = xna_motor_strength(left_motor)
              right = xna_motor_strength(right_motor)
              output = CNA::Native.library.pointer_for("C", 0)
              host = CNA::Runtime::Context.native_host("GamePad.SetVibration")
              CNA::Native.library.call("cna_gamepad_set_vibration", host.handle, player,
                                       left, right, output)
              output[0, 1].unpack1("C") != 0
            end

            private

            def native_player(value)
              player = PlayerIndex.coerce(value)
              {
                PlayerIndex::One => CNA::Native::Manifest::CONSTANTS.fetch("CNA_PLAYER_INDEX_ONE"),
                PlayerIndex::Two => CNA::Native::Manifest::CONSTANTS.fetch("CNA_PLAYER_INDEX_TWO"),
                PlayerIndex::Three => CNA::Native::Manifest::CONSTANTS.fetch("CNA_PLAYER_INDEX_THREE"),
                PlayerIndex::Four => CNA::Native::Manifest::CONSTANTS.fetch("CNA_PLAYER_INDEX_FOUR")
              }.fetch(player)
            end

            def native_dead_zone(value)
              dead_zone = GamePadDeadZone.coerce(value)
              {
                GamePadDeadZone::None => CNA::Native::Manifest::CONSTANTS.fetch("CNA_GAMEPAD_DEAD_ZONE_NONE"),
                GamePadDeadZone::IndependentAxes => CNA::Native::Manifest::CONSTANTS.fetch("CNA_GAMEPAD_DEAD_ZONE_INDEPENDENT_AXES"),
                GamePadDeadZone::Circular => CNA::Native::Manifest::CONSTANTS.fetch("CNA_GAMEPAD_DEAD_ZONE_CIRCULAR")
              }.fetch(dead_zone)
            end

            def xna_motor_strength(value)
              product = CNA::Runtime::Numeric.mul32(CNA::Runtime::Numeric.f32(value), 65_535.0)
              word = product.finite? ? product.truncate & 0xffff : 0
              CNA::Runtime::Numeric.div32(word, 65_535.0)
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

            def native_host(operation) = CNA::Runtime::Context.native_host(operation)
          end
          private_class_method :new
        end
      end
    end
  end
end
