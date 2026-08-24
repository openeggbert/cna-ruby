# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class MouseTest < Minitest::Test
  I = Microsoft::Xna::Framework::Input
  N = CNA::Runtime::Numeric
  RELEASED = I::ButtonState::Released
  PRESSED = I::ButtonState::Pressed

  def state(*values)
    I::MouseState.new(*values)
  end

  def asymmetric
    state(-17, 203, -120, PRESSED, RELEASED, PRESSED, PRESSED, RELEASED)
  end

  def test_button_state_is_exact_typed_frozen_non_flags_enum
    assert_equal [0, 1], [RELEASED.to_i, PRESSED.to_i]
    assert_instance_of I::ButtonState, RELEASED
    assert_instance_of I::ButtonState, PRESSED
    assert RELEASED.frozen?
    assert PRESSED.frozen?
    assert_raises(TypeError) { RELEASED | PRESSED }
    assert_raises(RangeError) { I::ButtonState.coerce(2) }
    assert_raises(TypeError) { I::ButtonState.coerce(true) }
  end

  def test_constructor_and_property_order_are_asymmetric_and_read_only
    value = asymmetric
    assert_equal [-17, 203, -120], [value.X, value.Y, value.ScrollWheelValue]
    assert_same PRESSED, value.LeftButton
    assert_same RELEASED, value.MiddleButton
    assert_same PRESSED, value.RightButton
    assert_same PRESSED, value.XButton1
    assert_same RELEASED, value.XButton2
    %i[X Y ScrollWheelValue LeftButton RightButton MiddleButton XButton1 XButton2].each do |name|
      refute_respond_to value, :"#{name}="
    end
  end

  def test_constructor_validates_arity_int32_and_button_state
    assert_raises(ArgumentError) { I::MouseState.new }
    assert_raises(ArgumentError) { I::MouseState.new(0, 0, 0, RELEASED, RELEASED, RELEASED, RELEASED) }
    assert_raises(RangeError) { state(2_147_483_648, 0, 0, RELEASED, RELEASED, RELEASED, RELEASED, RELEASED) }
    assert_raises(RangeError) { state(0, -2_147_483_649, 0, RELEASED, RELEASED, RELEASED, RELEASED, RELEASED) }
    assert_raises(RangeError) { state(0, 0, 2_147_483_648, RELEASED, RELEASED, RELEASED, RELEASED, RELEASED) }
    assert_raises(TypeError) { state(true, 0, 0, RELEASED, RELEASED, RELEASED, RELEASED, RELEASED) }
    assert_raises(TypeError) { state(0, 0, 0, true, RELEASED, RELEASED, RELEASED, RELEASED) }
    assert_raises(RangeError) { state(0, 0, 0, 2, RELEASED, RELEASED, RELEASED, RELEASED) }

    bridged = state(0, 0, 0, 1, 0, 1, 0, 1)
    assert [bridged.LeftButton, bridged.MiddleButton, bridged.RightButton,
            bridged.XButton1, bridged.XButton2].all? { |button| button.instance_of?(I::ButtonState) }
  end

  def test_equality_checks_every_xna_field_and_only_mouse_state_objects
    base = [-17, 203, -120, PRESSED, RELEASED, PRESSED, PRESSED, RELEASED]
    value = state(*base)
    assert value.Equals(state(*base))
    assert value == state(*base)
    refute value != state(*base)
    refute value.Equals(Object.new)
    refute value == nil

    alternatives = [18, -204, 121, RELEASED, PRESSED, RELEASED, RELEASED, PRESSED]
    base.each_index do |index|
      changed = base.dup
      changed[index] = alternatives[index]
      refute value.Equals(state(*changed)), "field #{index} must participate in equality"
      assert value != state(*changed)
    end
  end

  def test_hash_and_string_match_pinned_xna_behavior
    value = state(12, -3, 120, PRESSED, RELEASED, PRESSED, PRESSED, RELEASED)
    assert_equal(-120, value.GetHashCode)
    assert_equal(-120, value.hash)
    assert_equal "{X:12 Y:-3 Buttons:Left Right XButton1 Wheel:120}", value.ToString
    assert_equal value.ToString, value.to_s
    assert_equal "{X:0 Y:0 Buttons:None Wheel:0}",
                 state(0, 0, 0, RELEASED, RELEASED, RELEASED, RELEASED, RELEASED).ToString
    assert_equal "{X:1 Y:2 Buttons:Left Right Middle XButton1 XButton2 Wheel:3}",
                 state(1, 2, 3, PRESSED, PRESSED, PRESSED, PRESSED, PRESSED).ToString
  end

  def test_int32_extremes_and_value_copy_semantics
    minimum = -2_147_483_648
    maximum = 2_147_483_647
    value = state(minimum, maximum, minimum, PRESSED, RELEASED, PRESSED, RELEASED, PRESSED)
    assert_equal [minimum, maximum, minimum], [value.X, value.Y, value.ScrollWheelValue]
    assert_equal "{X:-2147483648 Y:2147483647 Buttons:Left Right XButton2 Wheel:-2147483648}", value.ToString
    assert_equal N.wrap_int32(minimum ^ maximum ^ 1 ^ 1 ^ 1 ^ minimum), value.GetHashCode

    duplicate = value.dup
    clone = value.freeze.clone
    refute_same value, duplicate
    refute_same value, clone
    assert_equal value, duplicate
    assert_equal value, clone
    assert clone.frozen?
    duplicate.instance_variable_set(:@X, 7)
    assert_equal minimum, value.X
    assert_equal 7, duplicate.X
  end

  def test_native_snapshot_conversion_copies_fields_and_button_bits
    native = CNA::Native::Layouts::MouseState.new
    native.write_i32(8, -9)
    native.write_i32(12, 27)
    native.write_i32(16, -240)
    native.write_i32(20, 999)
    native.write_u32(24, 1 | 4 | 16)
    left = I::MouseState.__send__(:from_native, native)
    right = I::MouseState.__send__(:from_native, native)
    assert_equal [-9, 27, -240, PRESSED, RELEASED, PRESSED, RELEASED, PRESSED],
                 [left.X, left.Y, left.ScrollWheelValue, left.LeftButton, left.MiddleButton,
                  left.RightButton, left.XButton1, left.XButton2]
    refute_same left, right
    left.instance_variable_set(:@Y, 1)
    assert_equal 27, right.Y
    refute left.instance_variables.any? { |name| left.instance_variable_get(name).instance_of?(Fiddle::Pointer) }
  end

  def test_intptr_mapping_is_signed_native_width_and_never_public_pointer
    bits = Fiddle::SIZEOF_VOIDP * 8
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1
    assert_equal bits, N.pointer_width_bits
    assert_equal [0, 7, maximum, -1, minimum], [0, 7, maximum, -1, minimum].map { |value| N.intptr(value) }
    assert_equal(-1, N.intptr_from_uint64_bits(N.intptr_to_uint64_bits(-1)))
    assert_equal minimum, N.intptr_from_uint64_bits(N.intptr_to_uint64_bits(minimum))
    assert_raises(RangeError) { N.intptr(maximum + 1) }
    assert_raises(RangeError) { N.intptr(minimum - 1) }
    assert_raises(TypeError) { N.intptr(Fiddle::Pointer.new(0)) }
  end

  def test_mouse_is_static_strictly_cased_and_requires_real_game_context
    assert_raises(NoMethodError) { I::Mouse.new }
    refute_respond_to I::Mouse, :get_state
    refute_respond_to I::Mouse, :set_position
    refute_respond_to I::Mouse, :window_handle
    assert_raises(CNA::InvalidBindingStateError) { I::Mouse.GetState }
    assert_raises(CNA::InvalidBindingStateError) { I::Mouse.SetPosition(0, 0) }
    assert_raises(CNA::InvalidBindingStateError) { I::Mouse.WindowHandle }
    assert_raises(CNA::InvalidBindingStateError) { I::Mouse.WindowHandle = 0 }
  end
end
