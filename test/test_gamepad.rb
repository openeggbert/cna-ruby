# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class GamePadTest < Minitest::Test
  F = Microsoft::Xna::Framework
  I = F::Input
  RELEASED = I::ButtonState::Released
  PRESSED = I::ButtonState::Pressed

  def test_buttons_values_flags_composition_and_validation
    expected = {
      DPadUp: 1, DPadDown: 2, DPadLeft: 4, DPadRight: 8, Start: 16, Back: 32,
      LeftStick: 64, RightStick: 128, LeftShoulder: 256, RightShoulder: 512,
      BigButton: 2_048, A: 4_096, B: 8_192, X: 16_384, Y: 32_768,
      RightThumbstickUp: 16_777_216, RightThumbstickDown: 33_554_432,
      RightThumbstickRight: 67_108_864, RightThumbstickLeft: 134_217_728,
      LeftThumbstickUp: 268_435_456, LeftThumbstickDown: 536_870_912,
      LeftThumbstickRight: 1_073_741_824, LeftThumbstickLeft: 2_097_152,
      RightTrigger: 4_194_304, LeftTrigger: 8_388_608
    }
    expected.each { |name, value| assert_equal value, I::Buttons.const_get(name).to_i }

    combined = I::Buttons::A | I::Buttons::DPadUp | I::Buttons::LeftThumbstickRight
    assert_instance_of I::Buttons, combined
    assert_equal 1_073_745_921, combined.to_i
    assert_equal I::Buttons::A, combined & I::Buttons::A
    assert_equal 0, (I::Buttons::A & I::Buttons::B).to_i
    assert_equal 0, I::Buttons.coerce(0).to_i
    assert_equal 0x7fe0_fbff, I::Buttons.coerce(0x7fe0_fbff).to_i
    assert_raises(RangeError) { I::Buttons.coerce(0x400) }
    assert_raises(RangeError) { I::Buttons.coerce(0x8000_0000) }
    assert_raises(TypeError) { I::Buttons.coerce(true) }
  end

  def test_non_flags_enums_are_exact_and_typed
    assert_equal [0, 1, 2], [I::GamePadDeadZone::None, I::GamePadDeadZone::IndependentAxes,
                             I::GamePadDeadZone::Circular].map(&:to_i)
    assert_equal [0, 1, 2, 3, 4, 5, 6, 7, 8, 768],
                 [I::GamePadType::Unknown, I::GamePadType::GamePad, I::GamePadType::Wheel,
                  I::GamePadType::ArcadeStick, I::GamePadType::FlightStick, I::GamePadType::DancePad,
                  I::GamePadType::Guitar, I::GamePadType::AlternateGuitar,
                  I::GamePadType::DrumKit, I::GamePadType::BigButtonPad].map(&:to_i)
    assert_raises(RangeError) { I::GamePadDeadZone.coerce(3) }
    assert_raises(RangeError) { I::GamePadType.coerce(9) }
    assert_raises(TypeError) { I::GamePadDeadZone::None | I::GamePadDeadZone::Circular }
  end

  def test_gamepad_buttons_projects_only_eleven_physical_properties
    mask = I::Buttons::A | I::Buttons::Back | I::Buttons::RightShoulder |
           I::Buttons::BigButton | I::Buttons::LeftTrigger | I::Buttons::DPadUp
    value = I::GamePadButtons.new(mask)
    assert_equal PRESSED, value.A
    assert_equal PRESSED, value.Back
    assert_equal PRESSED, value.RightShoulder
    assert_equal PRESSED, value.BigButton
    %i[B X Y Start LeftShoulder LeftStick RightStick].each do |property|
      assert_equal RELEASED, value.public_send(property)
    end
    refute_respond_to value, :LeftTrigger
    refute_respond_to value, :LeftThumbstickLeft
    assert_equal I::GamePadButtons.new(I::Buttons::A),
                 I::GamePadButtons.new(I::Buttons::A | I::Buttons::DPadUp | I::Buttons::LeftTrigger)
    assert_raises(TypeError) { I::GamePadButtons.new(I::GamePadDeadZone::None) }
  end

  def test_gamepad_buttons_equality_hash_and_string_are_xna_exact
    empty = I::GamePadButtons.new(I::Buttons.coerce(0))
    a = I::GamePadButtons.new(I::Buttons::A)
    two = I::GamePadButtons.new(I::Buttons::A | I::Buttons::B)
    dense = I::GamePadButtons.new(I::Buttons.coerce(0x0000_fbf0))
    assert empty.Equals(empty.dup)
    refute empty.Equals(Object.new)
    assert_equal 2_147_483_647, empty.GetHashCode
    assert_equal 1, a.GetHashCode
    assert_equal 2_147_483_647, two.GetHashCode
    assert_equal "{Buttons:None}", empty.ToString
    assert_equal "{Buttons:A B X Y LeftShoulder RightShoulder LeftStick RightStick Start Back BigButton}", dense.ToString
    assert_equal a, a.dup
    refute_same a, a.dup
  end

  def test_dpad_constructor_order_properties_hash_and_string
    dpad = I::GamePadDPad.new(PRESSED, RELEASED, PRESSED, RELEASED)
    assert_equal PRESSED, dpad.Up
    assert_equal RELEASED, dpad.Down
    assert_equal PRESSED, dpad.Left
    assert_equal RELEASED, dpad.Right
    assert_equal "{DPad:Up Left}", dpad.ToString
    assert_equal 2_147_483_647, dpad.GetHashCode
    asymmetric = I::GamePadDPad.new(RELEASED, RELEASED, RELEASED, PRESSED)
    assert_equal "{DPad:Right}", asymmetric.ToString
    assert_equal 1, asymmetric.GetHashCode
    assert asymmetric.Equals(asymmetric.dup)
    refute asymmetric.Equals("Right")
    assert_raises(TypeError) { I::GamePadDPad.new(true, RELEASED, RELEASED, RELEASED) }
  end

  def test_triggers_clamp_with_binary32_nan_infinity_and_signed_zero
    assert_equal [0.0, 1.0], [I::GamePadTriggers.new(-1.0, 2.0).Left,
                              I::GamePadTriggers.new(-1.0, 2.0).Right]
    middle = I::GamePadTriggers.new(0.5, 1.0)
    assert_equal 0.5, middle.Left
    assert_equal 1.0, middle.Right
    nan = I::GamePadTriggers.new(Float::NAN, Float::INFINITY)
    assert nan.Left.nan?
    assert_equal 1.0, nan.Right
    assert_equal 0.0, I::GamePadTriggers.new(-Float::INFINITY, 0).Left
    assert_equal 0, CNA::Runtime::Numeric.f32_bits(I::GamePadTriggers.new(-0.0, 0).Left)
    assert_equal 29_360_128, I::GamePadTriggers.new(0.25, 0.75).GetHashCode
    assert_equal 2_147_483_647, I::GamePadTriggers.new(0.0, 0.0).GetHashCode
    assert_equal "{Left:0.5 Right:1}", middle.ToString
    refute I::GamePadTriggers.new(Float::NAN, 0).Equals(I::GamePadTriggers.new(Float::NAN, 0))
  end

  def test_thumbsticks_square_clamp_nan_infinity_hash_string_and_copy
    source_left = F::Vector2.new(2.0, -2.0)
    source_right = F::Vector2.new(Float::NAN, Float::INFINITY)
    sticks = I::GamePadThumbSticks.new(source_left, source_right)
    assert_equal F::Vector2.new(1.0, -1.0), sticks.Left
    assert_equal F::Vector2.new(1.0, 1.0), sticks.Right
    source_left.X = 0.0
    assert_equal 1.0, sticks.Left.X
    first = sticks.Left
    second = sticks.Left
    refute_same first, second
    first.X = 0.25
    assert_equal 1.0, sticks.Left.X
    zero = I::GamePadThumbSticks.new(F::Vector2.Zero, F::Vector2.Zero)
    assert_equal 2_147_483_647, zero.GetHashCode
    fixture = I::GamePadThumbSticks.new(F::Vector2.new(0.25, -0.5),
                                        F::Vector2.new(0.75, -1.0))
    assert_equal "{Left:{X:0.25 Y:-0.5} Right:{X:0.75 Y:-1}}", fixture.ToString
    assert_equal 20_971_520, fixture.GetHashCode
    assert_raises(TypeError) { I::GamePadThumbSticks.new([0, 0], F::Vector2.Zero) }
  end

  def test_state_component_constructor_defaults_and_copies_boundaries
    sticks = I::GamePadThumbSticks.new(F::Vector2.new(0.5, -0.25), F::Vector2.Zero)
    triggers = I::GamePadTriggers.new(0.25, 0.75)
    buttons = I::GamePadButtons.new(I::Buttons::A)
    dpad = I::GamePadDPad.new(PRESSED, RELEASED, RELEASED, RELEASED)
    state = I::GamePadState.new(sticks, triggers, buttons, dpad)
    assert_equal true, state.IsConnected
    assert_equal 0, state.PacketNumber
    assert_equal sticks, state.ThumbSticks
    assert_equal triggers, state.Triggers
    assert_equal buttons, state.Buttons
    assert_equal dpad, state.DPad
    [state.ThumbSticks, state.Triggers, state.Buttons, state.DPad].zip(
      [state.ThumbSticks, state.Triggers, state.Buttons, state.DPad]
    ).each { |left, right| refute_same left, right }
    sticks.Left.X = -1.0
    triggers.instance_variable_set(:@Left, 1.0)
    buttons.instance_variable_set(:@mask, 0)
    dpad.instance_variable_set(:@Up, RELEASED)
    assert_equal 0.5, state.ThumbSticks.Left.X
    assert_equal 0.25, state.Triggers.Left
    assert_equal PRESSED, state.Buttons.A
    assert_equal PRESSED, state.DPad.Up
    returned = state.ThumbSticks
    returned.instance_variable_get(:@Left).X = -0.75
    assert_equal 0.5, state.ThumbSticks.Left.X
  end

  def test_state_array_constructor_null_empty_repeated_combined_and_validation
    zero = F::Vector2.Zero
    empty = I::GamePadState.new(zero, zero, 0.0, 0.0, [])
    null = I::GamePadState.new(zero, zero, 0.0, 0.0, nil)
    assert_equal empty, null
    assert_equal true, empty.IsConnected
    repeated = I::GamePadState.new(zero, zero, 0.0, 0.0, [I::Buttons::A, I::Buttons::A])
    combined = I::GamePadState.new(zero, zero, 0.0, 0.0,
                                   [I::Buttons::A | I::Buttons::B, I::Buttons::DPadRight])
    assert repeated.IsButtonDown(I::Buttons::A)
    assert combined.IsButtonDown(I::Buttons::A | I::Buttons::B | I::Buttons::DPadRight)
    ignored = I::GamePadState.new(zero, zero, 0.0, 0.0, [I::Buttons::LeftTrigger])
    refute ignored.IsButtonDown(I::Buttons::LeftTrigger)
    assert_raises(TypeError) { I::GamePadState.new(zero, zero, 0.0, 0.0, I::Buttons::A) }
    assert_raises(RangeError) { I::GamePadState.new(zero, zero, 0.0, 0.0, [I::Buttons::A, 0x400]) }
    assert_raises(TypeError) { I::GamePadState.new([0, 0], zero, 0.0, 0.0, []) }
  end

  def test_state_button_queries_require_all_bits_and_use_strict_xna_thresholds
    numeric = CNA::Runtime::Numeric
    at_left = numeric.div32(7_849.0, 32_767.0)
    over_left = numeric.div32(7_850.0, 32_767.0)
    at_trigger = numeric.div32(30.0, 255.0)
    over_trigger = numeric.div32(31.0, 255.0)
    at = I::GamePadState.new(F::Vector2.new(at_left, 0), F::Vector2.Zero,
                             at_trigger, 0.0, [I::Buttons::A])
    over = I::GamePadState.new(F::Vector2.new(over_left, 0), F::Vector2.Zero,
                               over_trigger, 0.0, [I::Buttons::A])
    refute at.IsButtonDown(I::Buttons::LeftThumbstickRight)
    refute at.IsButtonDown(I::Buttons::LeftTrigger)
    assert over.IsButtonDown(I::Buttons::LeftThumbstickRight)
    assert over.IsButtonDown(I::Buttons::LeftTrigger)
    assert over.IsButtonDown(I::Buttons::A | I::Buttons::LeftThumbstickRight | I::Buttons::LeftTrigger)
    refute over.IsButtonDown(I::Buttons::A | I::Buttons::B)
    assert over.IsButtonUp(I::Buttons::A | I::Buttons::B)
    assert over.IsButtonDown(I::Buttons.coerce(0))
    refute over.IsButtonUp(I::Buttons.coerce(0))
  end

  def test_state_equality_hash_string_and_native_private_fields
    native = CNA::Native::Layouts::GamePadState.new
    native.write_u8(8, 1)
    native.write_i32(12, -123)
    native.write_u32(16, I::Buttons::A.to_i | I::Buttons::DPadLeft.to_i |
                         I::Buttons::RightTrigger.to_i)
    native.write_f32(24, 0.25); native.write_f32(28, -0.5)
    native.write_f32(32, 0.75); native.write_f32(36, -1.0)
    native.write_f32(40, 0.125); native.write_f32(44, 1.0)
    state = I::GamePadState.__send__(:from_native, native)
    assert_equal true, state.IsConnected
    assert_equal(-123, state.PacketNumber)
    assert_equal PRESSED, state.Buttons.A
    assert_equal PRESSED, state.DPad.Left
    assert state.IsButtonDown(I::Buttons::A | I::Buttons::DPadLeft | I::Buttons::RightTrigger)
    assert_equal "{IsConnected:True}", state.ToString
    assert_equal state, state.dup
    refute_same state, state.dup
    disconnected = native.tap { |value| value.write_u8(8, 0) }
    other = I::GamePadState.__send__(:from_native, disconnected)
    refute_equal state, other
    assert_equal "{IsConnected:False}", other.ToString
    refute_equal state.GetHashCode, other.GetHashCode
  end

  def test_native_virtual_buttons_are_derived_from_xna_analog_rules_not_cna_mask_bits
    native = CNA::Native::Layouts::GamePadState.new
    native.write_u8(8, 1)
    native.write_u32(16, I::Buttons::LeftTrigger.to_i)
    independent = I::GamePadState.__send__(:from_native, native, I::GamePadDeadZone::IndependentAxes)
    refute independent.IsButtonDown(I::Buttons::LeftTrigger)

    native.write_u32(16, 0)
    native.write_f32(24, 0.01)
    native.write_f32(40, 0.01)
    independent = I::GamePadState.__send__(:from_native, native, I::GamePadDeadZone::IndependentAxes)
    assert independent.IsButtonDown(I::Buttons::LeftThumbstickRight)
    assert independent.IsButtonDown(I::Buttons::LeftTrigger)
    none = I::GamePadState.__send__(:from_native, native, I::GamePadDeadZone::None)
    refute none.IsButtonDown(I::Buttons::LeftThumbstickRight)
    refute none.IsButtonDown(I::Buttons::LeftTrigger)

    native.write_f32(24, 0.1)
    circular = I::GamePadState.__send__(:from_native, native, I::GamePadDeadZone::Circular)
    assert circular.IsButtonDown(I::Buttons::LeftThumbstickRight)
  end

  def test_capabilities_has_no_public_constructor_and_maps_every_native_field
    refute_respond_to I::GamePadCapabilities, :new
    assert_raises(NoMethodError) { I::GamePadCapabilities.new }
    native = CNA::Native::Layouts::GamePadCapabilities.new
    native.write_u32(8, 9)
    (12..36).each { |offset| native.write_u8(offset, offset.odd? ? 1 : 0) }
    caps = I::GamePadCapabilities.__send__(:from_native, native)
    assert_equal I::GamePadType::BigButtonPad, caps.GamePadType
    properties_by_offset = {
      IsConnected: 12, HasAButton: 13, HasBButton: 14, HasXButton: 15, HasYButton: 16,
      HasBackButton: 17, HasStartButton: 18, HasBigButton: 19, HasDPadUpButton: 20,
      HasDPadDownButton: 21, HasDPadLeftButton: 22, HasDPadRightButton: 23,
      HasLeftShoulderButton: 24, HasRightShoulderButton: 25, HasLeftStickButton: 26,
      HasRightStickButton: 27, HasLeftXThumbStick: 28, HasLeftYThumbStick: 29,
      HasRightXThumbStick: 30, HasRightYThumbStick: 31, HasLeftTrigger: 32,
      HasRightTrigger: 33, HasLeftVibrationMotor: 34, HasRightVibrationMotor: 35,
      HasVoiceSupport: 36
    }
    properties_by_offset.each do |property, offset|
      assert_equal offset.odd?, caps.public_send(property), property.to_s
    end
    copy = caps.dup
    refute_same caps, copy
    properties_by_offset.each_key { |property| assert_equal caps.public_send(property), copy.public_send(property) }
    native.write_u32(8, 99)
    assert_equal I::GamePadType::Unknown, I::GamePadCapabilities.__send__(:from_native, native).GamePadType
  end

  def test_gamepad_is_static_validates_context_and_xna_vibration_conversion
    assert_raises(NoMethodError) { I::GamePad.new }
    assert_raises(CNA::InvalidBindingStateError) { I::GamePad.GetState(F::PlayerIndex::One) }
    assert_raises(CNA::InvalidBindingStateError) { I::GamePad.GetCapabilities(F::PlayerIndex::One) }
    assert_raises(CNA::InvalidBindingStateError) { I::GamePad.SetVibration(F::PlayerIndex::One, 0, 0) }
    assert_raises(TypeError) { I::GamePad.GetState(I::GamePadDeadZone::None) }
    assert_raises(RangeError) { I::GamePad.GetState(F::PlayerIndex::One, 3) }

    conversion = ->(value) { I::GamePad.__send__(:xna_motor_strength, value) }
    assert_in_delta 1.0 / 65_535.0, conversion.call(-1.0), 1e-10
    assert_in_delta 32_767.0 / 65_535.0, conversion.call(0.5), 1e-7
    assert_equal 1.0, conversion.call(1.0)
    assert_in_delta 32_766.0 / 65_535.0, conversion.call(1.5), 1e-7
    assert_equal 0.0, conversion.call(Float::NAN)
    assert_equal 0.0, conversion.call(Float::INFINITY)
  end
end
