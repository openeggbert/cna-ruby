# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/microsoft/xna/framework/graphics"
require_relative "../lib/microsoft/xna/framework/input"

class GraphicsProfileTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  I = F::Input
  PROFILE = G::GraphicsProfile

  def test_graphics_require_exposes_exact_typed_frozen_non_flags_constants
    expected = {Reach: 0, HiDef: 1}

    assert_same PROFILE, G.const_get(:GraphicsProfile, false)
    refute F.const_defined?(:GraphicsProfile, false)
    assert_equal CNA::Runtime::EnumValue, PROFILE.superclass
    assert_equal expected.keys.sort, PROFILE.constants(false).sort
    expected.each do |name, raw|
      value = PROFILE.const_get(name, false)
      assert_instance_of PROFILE, value
      assert_predicate value, :frozen?
      assert_equal raw, value.value
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.name
    end
    assert_equal false, PROFILE.instance_variable_get(:@enum_flags)
    assert_equal 0, PROFILE.instance_variable_get(:@enum_mask)
    refute_includes PROFILE.constants(false), :value__
  end

  def test_declared_values_are_canonical_under_existing_ordinary_enum_policy
    assert_same PROFILE::Reach, PROFILE.coerce(0)
    assert_same PROFILE::HiDef, PROFILE.coerce(1)
    assert_same PROFILE::Reach, PROFILE.coerce(PROFILE::Reach)
    assert_same PROFILE::HiDef, PROFILE.coerce(PROFILE::HiDef)

    assert_equal "Reach", PROFILE::Reach.to_s
    assert_equal "Microsoft::Xna::Framework::Graphics::GraphicsProfile::HiDef", PROFILE::HiDef.inspect
    assert_equal 1, PROFILE::HiDef.to_i
  end

  def test_unknown_raw_values_non_integer_values_and_flags_operators_are_rejected
    [-1, 2, 2_147_483_647].each { |raw| assert_raises(RangeError) { PROFILE.coerce(raw) } }
    [nil, true, 1.0, "1", Object.new].each { |value| assert_raises(TypeError) { PROFILE.coerce(value) } }

    assert_raises(TypeError) { PROFILE::Reach | PROFILE::HiDef }
    assert_raises(TypeError) { PROFILE::HiDef & PROFILE::Reach }
  end

  def test_cross_type_values_are_not_accepted_or_equal
    foreign_values = [
      G::GraphicsDeviceStatus::Normal,
      F::DisplayOrientation::Default,
      G::SurfaceFormat::Color,
      G::SpriteSortMode::Deferred,
      F::PlayerIndex::One,
      I::GamePadDeadZone::None
    ]

    foreign_values.each do |value|
      assert_raises(TypeError) { PROFILE.coerce(value) }
      refute_equal PROFILE::Reach, value
      assert_nil PROFILE::Reach <=> value
    end
  end

  def test_language_support_adds_no_xna_identity_or_profile_functionality
    assert_respond_to PROFILE::Reach, :to_s
    assert_respond_to PROFILE::Reach, :inspect
    assert_respond_to PROFILE::Reach, :to_i
    refute_respond_to PROFILE::Reach, :ToString
    refute_respond_to PROFILE::Reach, :HasFlag
    refute_respond_to PROFILE::Reach, :FeatureLevel
    refute_respond_to PROFILE::Reach, :SupportsHiDef?

    refute_includes G::GraphicsDevice.public_instance_methods(false), :GraphicsProfile
    refute_includes F::GraphicsDeviceManager.public_instance_methods(false), :GraphicsProfile
    refute G.const_defined?(:GraphicsAdapter, false)
    # Foundation 25 added DisplayMode as a non-constructible managed descriptor; no adapter
    # enumerates one.
    assert G.const_defined?(:DisplayMode, false)
    assert G.const_defined?(:DisplayModeCollection, false)
    refute G.const_defined?(:GraphicsAdapter, false)
    # Foundation 24 added PresentationParameters as a managed descriptor; it creates no device.
    assert G.const_defined?(:PresentationParameters, false)
    refute F.const_defined?(:GraphicsDeviceInformation, false)
    refute F.const_defined?(:PreparingDeviceSettingsEventArgs, false)
  end
end
