# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class PackedVectorTest < Minitest::Test
  F = Microsoft::Xna::Framework
  PV = F::Graphics::PackedVector

  TYPE_SPECS = {
    PV::Alpha8 => [[0.0], 0xff],
    PV::Bgr565 => [[0.0, 0.0, 0.0], 0xffff],
    PV::Bgra4444 => [[0.0, 0.0, 0.0, 0.0], 0xffff],
    PV::Bgra5551 => [[0.0, 0.0, 0.0, 0.0], 0xffff],
    PV::Byte4 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff],
    PV::HalfSingle => [[0.0], 0xffff],
    PV::HalfVector2 => [[0.0, 0.0], 0xffff_ffff],
    PV::HalfVector4 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff_ffff_ffff],
    PV::NormalizedByte2 => [[0.0, 0.0], 0xffff],
    PV::NormalizedByte4 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff],
    PV::NormalizedShort2 => [[0.0, 0.0], 0xffff_ffff],
    PV::NormalizedShort4 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff_ffff_ffff],
    PV::Rg32 => [[0.0, 0.0], 0xffff_ffff],
    PV::Rgba1010102 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff],
    PV::Rgba64 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff_ffff_ffff],
    PV::Short2 => [[0.0, 0.0], 0xffff_ffff],
    PV::Short4 => [[0.0, 0.0, 0.0, 0.0], 0xffff_ffff_ffff_ffff]
  }.freeze

  TWO_COMPONENT_TYPES = [PV::HalfVector2, PV::NormalizedByte2, PV::NormalizedShort2, PV::Rg32, PV::Short2].freeze
  FOUR_COMPONENT_TYPES = [
    PV::Bgra4444, PV::Bgra5551, PV::Byte4, PV::HalfVector4, PV::NormalizedByte4,
    PV::NormalizedShort4, PV::Rgba1010102, PV::Rgba64, PV::Short4
  ].freeze
  EXPLICIT_TO_VECTOR4_TYPES = [
    PV::Alpha8, PV::Bgr565, PV::HalfSingle, PV::HalfVector2, PV::NormalizedByte2,
    PV::NormalizedShort2, PV::Rg32, PV::Short2
  ].freeze

  def bits(value) = CNA::Runtime::Numeric.f32_bits(value)

  def test_interfaces_are_modules_and_concrete_types_retain_both_identities
    assert_instance_of Module, PV::IPackedVector
    refute_instance_of Class, PV::IPackedVector
    assert_instance_of Module, PV::IPackedVectorOfT
    assert_includes PV::IPackedVectorOfT.ancestors, PV::IPackedVector

    TYPE_SPECS.each_key do |type|
      assert_includes type.ancestors, PV::IPackedVectorOfT
      assert_includes type.ancestors, PV::IPackedVector
      assert_includes type.private_instance_methods, :PackFromVector4
    end
    EXPLICIT_TO_VECTOR4_TYPES.each do |type|
      assert_includes type.private_instance_methods, :ToVector4
      refute_includes type.public_instance_methods, :ToVector4
    end
    (FOUR_COMPONENT_TYPES - EXPLICIT_TO_VECTOR4_TYPES).each do |type|
      assert_includes type.public_instance_methods, :ToVector4
    end
  end

  def test_packed_value_setters_enforce_exact_unsigned_widths
    TYPE_SPECS.each do |type, (arguments, maximum)|
      value = type.new(*arguments)
      value.PackedValue = maximum
      assert_equal maximum, value.PackedValue, type.name
      assert_raises(RangeError, type.name) { value.PackedValue = -1 }
      assert_raises(RangeError, type.name) { value.PackedValue = maximum + 1 }
      assert_raises(TypeError, type.name) { value.PackedValue = 1.0 }
    end
  end

  def test_constructor_overloads_are_deterministic_and_copy_vector_values
    vector3 = F::Vector3.new(0.25, 0.5, 0.75)
    assert_equal PV::Bgr565.new(0.25, 0.5, 0.75).PackedValue, PV::Bgr565.new(vector3).PackedValue

    TWO_COMPONENT_TYPES.each do |type|
      vector = F::Vector2.new(0.25, -0.5)
      value = type.new(vector)
      assert_equal type.new(0.25, -0.5).PackedValue, value.PackedValue, type.name
      packed = value.PackedValue
      vector.X = 1.0
      assert_equal packed, value.PackedValue, type.name
      assert_raises(ArgumentError, type.name) { type.new(F::Vector3.Zero) }
      assert_raises(ArgumentError, type.name) { type.new(0.0) }
    end

    FOUR_COMPONENT_TYPES.each do |type|
      vector = F::Vector4.new(0.25, -0.5, 0.75, 1.0)
      value = type.new(vector)
      assert_equal type.new(0.25, -0.5, 0.75, 1.0).PackedValue, value.PackedValue, type.name
      packed = value.PackedValue
      vector.W = 0.0
      assert_equal packed, value.PackedValue, type.name
      assert_raises(ArgumentError, type.name) { type.new(F::Vector3.Zero) }
      assert_raises(ArgumentError, type.name) { type.new(0.0, 0.0) }
    end
    assert_raises(TypeError) { PV::Alpha8.new("0") }
    assert_raises(TypeError) { PV::HalfSingle.new(Object.new) }
    assert_raises(ArgumentError) { PV::Bgr565.new(0.0, 0.0) }
  end

  def test_pack_from_vector4_mutates_and_consumes_the_reference_lanes
    lanes = F::Vector4.new(-2.0, 0.5, 2.0, 0.25)
    expected_arguments = {
      PV::Alpha8 => [0.25], PV::Bgr565 => [-2.0, 0.5, 2.0], PV::HalfSingle => [-2.0]
    }
    TWO_COMPONENT_TYPES.each { |type| expected_arguments[type] = [-2.0, 0.5] }
    FOUR_COMPONENT_TYPES.each { |type| expected_arguments[type] = [-2.0, 0.5, 2.0, 0.25] }

    TYPE_SPECS.each do |type, (initial, _maximum)|
      value = type.new(*initial)
      assert_nil value.__send__(:PackFromVector4, lanes), type.name
      assert_equal type.new(*expected_arguments.fetch(type)).PackedValue, value.PackedValue, type.name
      assert_raises(TypeError, type.name) { value.__send__(:PackFromVector4, F::Vector3.Zero) }
    end
  end

  def test_interface_vector4_expansion_and_fresh_results
    alpha = PV::Alpha8.new(0.5).__send__(:ToVector4)
    assert_equal [0, 0, 0, 0x3f00_8081], [alpha.X, alpha.Y, alpha.Z, alpha.W].map { |v| bits(v) }

    bgr = PV::Bgr565.new(1.0, 0.0, 0.5)
    expanded = bgr.__send__(:ToVector4)
    assert_equal 0x3f80_0000, bits(expanded.W)
    refute_same expanded, bgr.__send__(:ToVector4)

    ([PV::HalfSingle] + TWO_COMPONENT_TYPES).each do |type|
      initial = TYPE_SPECS.fetch(type).first
      value = type.new(*initial)
      expanded_value = value.__send__(:ToVector4)
      if type == PV::HalfSingle
        assert_equal [0, 0, 0x3f80_0000], [expanded_value.Y, expanded_value.Z, expanded_value.W].map { |v| bits(v) }
      else
        assert_equal [0, 0x3f80_0000], [expanded_value.Z, expanded_value.W].map { |v| bits(v) }
      end
      refute_same expanded_value, value.__send__(:ToVector4), type.name
    end
  end

  def test_reference_packed_bits_cover_domains_rounding_and_lane_order
    assert_equal 0x80, PV::Alpha8.new(0.5).PackedValue
    assert_equal 0xf800, PV::Bgr565.new(1.0, 0.0, 0.0).PackedValue
    assert_equal 0x07e0, PV::Bgr565.new(0.0, 1.0, 0.0).PackedValue
    assert_equal 0x001f, PV::Bgr565.new(0.0, 0.0, 1.0).PackedValue
    assert_equal 0x0f00, PV::Bgra4444.new(1.0, 0.0, 0.0, 0.0).PackedValue
    assert_equal 0xf000, PV::Bgra4444.new(0.0, 0.0, 0.0, 1.0).PackedValue
    assert_equal 0, PV::Bgra5551.new(0.0, 0.0, 0.0, 0.5).PackedValue
    assert_equal 0x8000, PV::Bgra5551.new(0.0, 0.0, 0.0, 0.500_000_06).PackedValue

    assert_equal 0xff80_0100, PV::Byte4.new(-1.0, 1.0, 127.5, 300.0).PackedValue
    assert_equal 0x0402_0200, PV::Byte4.new(0.5, 1.5, 2.5, 3.5).PackedValue
    assert_equal 0x7f7f_0081, PV::NormalizedByte4.new(-1.0, 0.0, 1.0, 2.0).PackedValue
    assert_equal 0x7fff_7fff_0000_8001, PV::NormalizedShort4.new(-1.0, 0.0, 1.0, 2.0).PackedValue
    assert_equal 0xffff, PV::Rg32.new(1.0, 0.0).PackedValue
    assert_equal 0xffff_0000, PV::Rg32.new(0.0, 1.0).PackedValue
    assert_equal 0x0000_03ff, PV::Rgba1010102.new(1.0, 0.0, 0.0, 0.0).PackedValue
    assert_equal 0xc000_0000, PV::Rgba1010102.new(0.0, 0.0, 0.0, 1.0).PackedValue
    assert_equal 0xffff_0000_0000_0000, PV::Rgba64.new(0.0, 0.0, 0.0, 1.0).PackedValue
    assert_equal 0x7fff_8000, PV::Short2.new(-32_768.0, 32_767.0).PackedValue
    assert_equal 0x0002_0000_fffe_0000, PV::Short4.new(-0.5, -1.5, 0.5, 1.5).PackedValue
  end

  def test_xna_half_conversion_edges_ties_and_signed_canonicalization
    cases = {
      0x0000_0000 => [0x0000, 0x0000_0000],
      0x8000_0000 => [0x8000, 0x8000_0000],
      0x3300_0000 => [0x0000, 0x0000_0000],
      0x3380_0000 => [0x0001, 0x3380_0000],
      0x387f_c000 => [0x03ff, 0x387f_c000],
      0x3880_0000 => [0x0400, 0x3880_0000],
      0x3f80_1000 => [0x3c00, 0x3f80_0000],
      0x3f80_3000 => [0x3c02, 0x3f80_4000],
      0x477f_e000 => [0x7bff, 0x477f_e000],
      0x477f_f000 => [0x7c00, 0x4780_0000],
      0x7f80_0000 => [0x7fff, 0x47ff_e000],
      0xff80_0000 => [0xffff, 0xc7ff_e000],
      0x7fc1_2345 => [0x7fff, 0x47ff_e000],
      0xffc1_2345 => [0xffff, 0xc7ff_e000]
    }
    cases.each do |single_bits, (half_bits, decoded_bits)|
      value = PV::HalfSingle.new(CNA::Runtime::Numeric.f32_from_bits(single_bits))
      assert_equal half_bits, value.PackedValue, single_bits.to_s(16)
      assert_equal decoded_bits, bits(value.ToSingle), single_bits.to_s(16)
    end
  end

  def test_value_semantics_equality_hash_and_string_use_exact_packed_bits
    TYPE_SPECS.each do |type, (arguments, maximum)|
      value = type.new(*arguments)
      value.PackedValue = maximum
      duplicate = value.dup
      clone = value.clone
      assert_equal value, duplicate, type.name
      assert value.Equals(clone), type.name
      refute_same value, duplicate, type.name
      duplicate.PackedValue = 0
      refute_equal value, duplicate, type.name
      assert value != duplicate, type.name
    end

    left = PV::HalfSingle.new(0.0)
    right = PV::HalfSingle.new(0.0)
    left.PackedValue = 0x7c01
    right.PackedValue = 0x7c02
    refute_equal left, right

    alpha = PV::Alpha8.new(0.0)
    alpha.PackedValue = 0xff
    assert_equal 255, alpha.GetHashCode
    byte = PV::Byte4.new(F::Vector4.Zero)
    byte.PackedValue = 0xffff_ffff
    assert_equal(-1, byte.GetHashCode)
    wide = PV::HalfVector4.new(F::Vector4.Zero)
    wide.PackedValue = 0xfedc_ba98_7654_3210
    assert_equal(-2_004_318_072, wide.GetHashCode)
    wide.PackedValue = 0xffff_ffff_ffff_ffff
    assert_equal 0, wide.GetHashCode

    assert_equal "FF", alpha.ToString
    assert_equal "FFFFFFFF", byte.ToString
    assert_equal "{X:-131008 Y:-131008 Z:-131008 W:-131008}", wide.ToString
    rgba = PV::Rgba64.new(F::Vector4.Zero)
    rgba.PackedValue = 0xffff_ffff_ffff_ffff
    assert_equal "FFFFFFFFFFFFFFFF", rgba.ToString
    assert_equal "0.333252", PV::HalfSingle.new(1.0 / 3.0).ToString
    assert_equal "{X:1 Y:-2}", PV::HalfVector2.new(1.0, -2.0).ToString
    assert_equal "{X:1 Y:-2 Z:0.5 W:0}", PV::HalfVector4.new(1.0, -2.0, 0.5, -0.0).ToString
  end

  def test_private_helpers_do_not_leak_into_the_xna_namespace
    refute PV.const_defined?(:PackedMath, false)
    refute PV.const_defined?(:HalfHelper, false)
    refute PV.const_defined?(:BitPacker, false)
    assert CNA::Runtime.const_defined?(:PackedVectorPacking, false)
    refute_includes PV::Alpha8.public_instance_methods, :initialize_packed
    refute_includes PV::Alpha8.public_instance_methods, :pack_unorm
  end
end
