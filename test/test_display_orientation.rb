# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/microsoft/xna/framework"

class DisplayOrientationTest < Minitest::Test
  F = Microsoft::Xna::Framework
  ORIENTATION = F::DisplayOrientation

  def test_root_framework_require_exposes_exact_typed_frozen_flags_constants
    expected = {
      Default: 0,
      LandscapeLeft: 1,
      LandscapeRight: 2,
      Portrait: 4
    }

    assert_same ORIENTATION, F.const_get(:DisplayOrientation, false)
    assert_equal expected.keys.sort, ORIENTATION.constants(false).sort
    expected.each do |name, raw|
      value = ORIENTATION.const_get(name, false)
      assert_instance_of ORIENTATION, value
      assert_predicate value, :frozen?
      assert_equal raw, value.value
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.name
    end
    assert_equal true, ORIENTATION.instance_variable_get(:@enum_flags)
    assert_equal 0x7, ORIENTATION.instance_variable_get(:@enum_mask)
    refute_includes ORIENTATION.constants(false), :value__
  end

  def test_named_values_and_zero_are_canonical_under_existing_coerce_policy
    assert_same ORIENTATION::Default, ORIENTATION.coerce(0)
    assert_same ORIENTATION::LandscapeLeft, ORIENTATION.coerce(1)
    assert_same ORIENTATION::LandscapeRight, ORIENTATION.coerce(2)
    assert_same ORIENTATION::Portrait, ORIENTATION.coerce(4)
    assert_same ORIENTATION::Portrait, ORIENTATION.coerce(ORIENTATION::Portrait)
    assert_equal "Default", ORIENTATION::Default.to_s
    assert_equal "Microsoft::Xna::Framework::DisplayOrientation::Default", ORIENTATION::Default.inspect

    combined = ORIENTATION.coerce(3)
    assert_instance_of ORIENTATION, combined
    assert_predicate combined, :frozen?
    assert_equal 3, combined.to_i
    assert_same combined, ORIENTATION.coerce(3)
    assert_equal "3", combined.to_s
    assert_equal "Microsoft::Xna::Framework::DisplayOrientation::3", combined.inspect
  end

  def test_flags_or_preserves_every_valid_combination
    combinations = {
      3 => ORIENTATION::LandscapeLeft | ORIENTATION::LandscapeRight,
      5 => ORIENTATION::LandscapeLeft | ORIENTATION::Portrait,
      6 => ORIENTATION::LandscapeRight | ORIENTATION::Portrait,
      7 => ORIENTATION::LandscapeLeft | ORIENTATION::LandscapeRight | ORIENTATION::Portrait
    }
    combinations.each do |raw, value|
      assert_instance_of ORIENTATION, value
      assert_predicate value, :frozen?
      assert_equal raw, value.to_i
      assert_same value, ORIENTATION.coerce(raw)
    end
  end

  def test_flags_and_returns_canonical_named_values
    left_portrait = ORIENTATION::LandscapeLeft | ORIENTATION::Portrait
    all = ORIENTATION.coerce(7)

    assert_same ORIENTATION::LandscapeLeft, left_portrait & ORIENTATION::LandscapeLeft
    assert_same ORIENTATION::Default, left_portrait & ORIENTATION::LandscapeRight
    assert_same ORIENTATION::Portrait, all & ORIENTATION::Portrait
    assert_same ORIENTATION::Default, ORIENTATION::Default & ORIENTATION::Portrait
  end

  def test_unknown_bits_cross_type_composition_and_extra_surface_are_rejected
    [8, 9, 0x100].each { |raw| assert_raises(RangeError) { ORIENTATION.coerce(raw) } }
    [nil, true, Object.new].each { |value| assert_raises(TypeError) { ORIENTATION.coerce(value) } }

    require_relative "../lib/microsoft/xna/framework/graphics"
    require_relative "../lib/microsoft/xna/framework/input"
    assert_raises(TypeError) do
      ORIENTATION::LandscapeLeft | F::Graphics::SpriteEffects::FlipHorizontally
    end
    assert_raises(TypeError) { ORIENTATION::LandscapeLeft | F::Input::Buttons::DPadUp }
    assert_raises(TypeError) { ORIENTATION::LandscapeLeft | F::PlayerIndex::One }

    refute F::Graphics.const_defined?(:DisplayOrientation, false)
    refute_respond_to ORIENTATION::Portrait, :ToString
    refute_respond_to ORIENTATION::Portrait, :HasFlag
    refute_respond_to ORIENTATION::Portrait, :Apply
    # GameWindow arrived in Foundation 48 from its own IL, and it reads CurrentOrientation from
    # the canonical route while refusing SetSupportedOrientations, for which the ABI has none.
    # `GraphicsDeviceManager.SupportedOrientations` exists now, and its default really is this
    # enum's `Default` -- the CLR zero, since the manager's constructor never assigns it. What this
    # milestone claimed is that **it** added no orientation surface, and `GameWindow` still refuses
    # `SetSupportedOrientations`, for which the ABI has no window-level route.
    refute F::GameWindow.public_method_defined?(:SetSupportedOrientations)
    refute F::GameWindow.public_method_defined?(:CurrentOrientation=)
  end
end
