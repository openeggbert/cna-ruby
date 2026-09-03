# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/microsoft/xna/framework/graphics"
require_relative "../lib/microsoft/xna/framework/input"

class GraphicsDeviceStatusTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  I = F::Input
  STATUS = G::GraphicsDeviceStatus

  def test_graphics_require_exposes_exact_typed_frozen_non_flags_constants
    expected = {Normal: 0, Lost: 1, NotReset: 2}

    assert_same STATUS, G.const_get(:GraphicsDeviceStatus, false)
    refute F.const_defined?(:GraphicsDeviceStatus, false)
    assert_equal CNA::Runtime::EnumValue, STATUS.superclass
    assert_equal expected.keys.sort, STATUS.constants(false).sort
    expected.each do |name, raw|
      value = STATUS.const_get(name, false)
      assert_instance_of STATUS, value
      assert_predicate value, :frozen?
      assert_equal raw, value.value
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.name
    end
    assert_equal false, STATUS.instance_variable_get(:@enum_flags)
    assert_equal 0, STATUS.instance_variable_get(:@enum_mask)
    refute_includes STATUS.constants(false), :value__
  end

  def test_declared_values_are_canonical_under_existing_ordinary_enum_policy
    assert_same STATUS::Normal, STATUS.coerce(0)
    assert_same STATUS::Lost, STATUS.coerce(1)
    assert_same STATUS::NotReset, STATUS.coerce(2)
    assert_same STATUS::NotReset, STATUS.coerce(STATUS::NotReset)

    assert_equal "Normal", STATUS::Normal.to_s
    assert_equal "Microsoft::Xna::Framework::Graphics::GraphicsDeviceStatus::Lost", STATUS::Lost.inspect
    assert_equal 2, STATUS::NotReset.to_i
  end

  def test_unknown_raw_values_and_flags_operators_are_rejected
    [-1, 3, 2_147_483_647].each { |raw| assert_raises(RangeError) { STATUS.coerce(raw) } }
    [nil, true, 1.0, "1", Object.new].each { |value| assert_raises(TypeError) { STATUS.coerce(value) } }

    assert_raises(TypeError) { STATUS::Normal | STATUS::Lost }
    assert_raises(TypeError) { STATUS::NotReset & STATUS::Lost }
  end

  def test_cross_type_values_are_not_accepted_or_equal
    foreign_values = [
      F::DisplayOrientation::Default,
      G::SpriteEffects::None,
      I::Buttons::DPadUp,
      G::SurfaceFormat::Color,
      F::PlayerIndex::One
    ]

    foreign_values.each do |value|
      assert_raises(TypeError) { STATUS.coerce(value) }
      refute_equal STATUS::Normal, value
      assert_nil STATUS::Normal <=> value
    end
  end

  def test_language_support_adds_no_xna_identity_or_device_status_functionality
    assert_respond_to STATUS::Normal, :to_s
    assert_respond_to STATUS::Normal, :inspect
    assert_respond_to STATUS::Normal, :to_i
    refute_respond_to STATUS::Normal, :ToString
    refute_respond_to STATUS::Normal, :HasFlag
    refute_respond_to STATUS::Normal, :Reset

    # The device property was selected by Foundation 90 and `Present`/`Reset` in Foundation 92;
    # the enum itself still adds nothing.
    assert_includes G::GraphicsDevice.public_instance_methods(false), :GraphicsDeviceStatus
    refute F.const_defined?(:GraphicsProfile, false)
    # Foundation 24 added PresentationParameters as a managed descriptor; it creates no device.
    assert G.const_defined?(:PresentationParameters, false)
    refute G.const_defined?(:GraphicsAdapter, false)
  end
end
