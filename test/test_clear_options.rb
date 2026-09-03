# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../lib/microsoft/xna/framework/graphics"
require_relative "../lib/microsoft/xna/framework/input"

class ClearOptionsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  I = F::Input
  OPTIONS = G::ClearOptions

  def test_graphics_require_exposes_exact_typed_frozen_flags_constants
    expected = {Target: 1, DepthBuffer: 2, Stencil: 4}

    assert_same OPTIONS, G.const_get(:ClearOptions, false)
    refute F.const_defined?(:ClearOptions, false)
    refute G::GraphicsDevice.const_defined?(:ClearOptions, false)
    assert_equal CNA::Runtime::EnumValue, OPTIONS.superclass
    assert_equal expected.keys.sort, OPTIONS.constants(false).sort
    expected.each do |name, raw|
      value = OPTIONS.const_get(name, false)
      assert_instance_of OPTIONS, value
      assert_predicate value, :frozen?
      assert_equal raw, value.value
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.name
    end
    assert_equal true, OPTIONS.instance_variable_get(:@enum_flags)
    assert_equal 0x7, OPTIONS.instance_variable_get(:@enum_mask)
    refute_includes OPTIONS.constants(false), :value__
  end

  def test_no_xna_named_zero_or_all_constant_is_invented
    %i[None Default Empty All].each do |name|
      refute OPTIONS.const_defined?(name, false), name.to_s
    end
  end

  def test_named_and_unnamed_values_are_canonical_typed_and_frozen
    assert_same OPTIONS::Target, OPTIONS.coerce(1)
    assert_same OPTIONS::DepthBuffer, OPTIONS.coerce(2)
    assert_same OPTIONS::Stencil, OPTIONS.coerce(4)
    assert_same OPTIONS::Target, OPTIONS.coerce(OPTIONS::Target)

    (0..7).each do |raw|
      value = OPTIONS.coerce(raw)
      assert_instance_of OPTIONS, value
      assert_predicate value, :frozen?
      assert_equal raw, value.to_i
      assert_same value, OPTIONS.coerce(raw)
    end

    zero = OPTIONS.coerce(0)
    assert_equal "0", zero.to_s
    assert_equal "Microsoft::Xna::Framework::Graphics::ClearOptions::0", zero.inspect
    assert_equal 0, zero.value
    assert_equal "0", zero.name
    assert_equal "Target", OPTIONS::Target.to_s
    assert_equal "DepthBuffer", OPTIONS::DepthBuffer.to_s
    assert_equal "Stencil", OPTIONS::Stencil.to_s
    assert_equal "3", OPTIONS.coerce(3).to_s
    assert_equal "7", OPTIONS.coerce(7).to_s
  end

  def test_or_and_composition_preserves_exact_controlled_mask
    combinations = {
      3 => OPTIONS::Target | OPTIONS::DepthBuffer,
      5 => OPTIONS::Target | OPTIONS::Stencil,
      6 => OPTIONS::DepthBuffer | OPTIONS::Stencil,
      7 => OPTIONS::Target | OPTIONS::DepthBuffer | OPTIONS::Stencil
    }
    combinations.each do |raw, value|
      assert_instance_of OPTIONS, value
      assert_predicate value, :frozen?
      assert_equal raw, value.to_i
      assert_same value, OPTIONS.coerce(raw)
    end

    assert_same OPTIONS::Target, combinations.fetch(3) & OPTIONS::Target
    assert_same OPTIONS::Stencil, combinations.fetch(5) & OPTIONS::Stencil
    zero = OPTIONS::Target & OPTIONS::DepthBuffer
    assert_same OPTIONS.coerce(0), zero
    assert_instance_of OPTIONS, zero
    assert_predicate zero, :frozen?
    assert_equal 0, zero.to_i
  end

  def test_unknown_bits_negative_values_and_non_integers_are_rejected
    [8, 9, 0x100, -1].each { |raw| assert_raises(RangeError) { OPTIONS.coerce(raw) } }
    [nil, true, false, 1.0, "1", Object.new].each do |value|
      assert_raises(TypeError) { OPTIONS.coerce(value) }
    end
  end

  def test_cross_type_operations_equality_and_extra_surface_are_rejected
    foreign_values = [
      F::DisplayOrientation::LandscapeLeft,
      G::SpriteEffects::FlipHorizontally,
      I::Buttons::A,
      G::GraphicsDeviceStatus::Normal,
      G::GraphicsProfile::Reach,
      G::SurfaceFormat::Color
    ]
    foreign_values.each do |value|
      assert_raises(TypeError) { OPTIONS.coerce(value) }
      refute_equal OPTIONS::Target, value
      assert_nil OPTIONS::Target <=> value
      assert_raises(TypeError) { OPTIONS::Target | value }
      assert_raises(TypeError) { OPTIONS::Target & value }
    end

    %i[ToString HasFlag Contains Includes Target? DepthBuffer? Stencil? None? All? Mask ValidBits].each do |name|
      refute_respond_to OPTIONS::Target, name
    end
    assert_equal 1, G::GraphicsDevice.instance_method(:Clear).arity
    refute CNA::Native::Manifest::CONSTANTS.keys.any? { |name| name.include?("CLEAR_OPTIONS") }
  end

  def test_generic_flags_policy_supports_a_mask_without_a_declared_zero
    enum = Class.new(CNA::Runtime::EnumValue)
    enum.extend(CNA::Runtime::EnumType)
    enum.define_values({"One" => 1, "Two" => 2, "Four" => 4}, flags: true)

    refute enum.const_defined?(:None, false)
    zero = enum.coerce(0)
    assert_instance_of enum, zero
    assert_predicate zero, :frozen?
    assert_equal 0, zero.to_i
    assert_equal "0", zero.to_s
    assert_same zero, enum.coerce(0)
    assert_equal 7, (enum::One | enum::Two | enum::Four).to_i
    assert_same zero, enum::One & enum::Two
    assert_raises(RangeError) { enum.coerce(8) }
  end

  def test_isolated_graphics_require_does_not_load_cna_native_library
    library = File.expand_path("../lib", __dir__)
    script = <<~'RUBY'
      require "microsoft/xna/framework/graphics"
      options = Microsoft::Xna::Framework::Graphics::ClearOptions
      abort "wrong zero" unless options.coerce(0).to_i == 0
      abort "native library loaded" if CNA::Native.instance_variable_defined?(:@library)
    RUBY
    environment = {"CNA_NATIVE_LIBRARY" => nil, "RUBYLIB" => ENV["RUBYLIB"], "RUBYOPT" => nil}
    ruby = ENV.fetch("RUBY_EXECUTABLE", RbConfig.ruby)
    output, error, status = Open3.capture3(environment, ruby, "-I#{library}", "-e", script)
    assert status.success?, "#{output}#{error}"
  end
end
