# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class VertexElementTest < Minitest::Test
  G = Microsoft::Xna::Framework::Graphics
  FORMAT = G::VertexElementFormat
  USAGE = G::VertexElementUsage
  VERTEX = G::VertexElement
  INT32_MIN = -2_147_483_648
  INT32_MAX = 2_147_483_647

  FORMAT_VALUES = {
    Single: 0, Vector2: 1, Vector3: 2, Vector4: 3, Color: 4, Byte4: 5,
    Short2: 6, Short4: 7, NormalizedShort2: 8, NormalizedShort4: 9,
    HalfVector2: 10, HalfVector4: 11
  }.freeze
  USAGE_VALUES = {
    Position: 0, Color: 1, TextureCoordinate: 2, Normal: 3, Binormal: 4,
    Tangent: 5, BlendIndices: 6, BlendWeight: 7, Depth: 8, Fog: 9,
    PointSize: 10, Sample: 11, TessellateFactor: 12
  }.freeze

  def test_enums_are_exact_typed_frozen_non_flags_int32_values
    FORMAT_VALUES.each do |name, raw|
      value = FORMAT.const_get(name, false)
      assert_instance_of FORMAT, value
      assert_predicate value, :frozen?
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.to_s
    end
    USAGE_VALUES.each do |name, raw|
      value = USAGE.const_get(name, false)
      assert_instance_of USAGE, value
      assert_predicate value, :frozen?
      assert_equal raw, value.to_i
      assert_equal name.to_s, value.to_s
    end

    refute FORMAT.instance_variable_get(:@enum_flags)
    refute USAGE.instance_variable_get(:@enum_flags)
    refute_includes FORMAT.constants(false), :value__
    refute_includes USAGE.constants(false), :value__
  end

  def test_enum_policy_reuses_the_existing_named_value_bridge_and_rejects_unnamed_values
    assert_same FORMAT::Vector3, FORMAT.coerce(2)
    assert_same USAGE::Tangent, USAGE.coerce(5)
    assert_raises(RangeError) { FORMAT.coerce(12) }
    assert_raises(RangeError) { USAGE.coerce(13) }
    assert_raises(RangeError) { USAGE.coerce(-1) }
    assert_raises(TypeError) { FORMAT.coerce(USAGE::Position) }
    assert_raises(TypeError) { USAGE.coerce(FORMAT::Single) }
    assert_raises(TypeError) { FORMAT::Single | FORMAT::Vector2 }
    assert_raises(TypeError) { USAGE::Position | USAGE::Color }
  end

  def test_enums_expose_no_vertex_declaration_or_format_helper_surface
    helper_names = %i[SizeInBytes ComponentCount Normalized? String ToString GetSize Stride ElementSize]
    [FORMAT, USAGE, FORMAT::Single, USAGE::Position].each do |value|
      helper_names.each { |name| refute_respond_to value, name }
    end
  end

  def test_default_and_four_argument_construction
    zero = VERTEX.new
    assert_equal 0, zero.Offset
    assert_same FORMAT::Single, zero.VertexElementFormat
    assert_same USAGE::Position, zero.VertexElementUsage
    assert_equal 0, zero.UsageIndex
    assert_equal VERTEX.new(0, FORMAT::Single, USAGE::Position, 0), zero

    value = VERTEX.new(12, FORMAT::Vector3, USAGE::TextureCoordinate, 7)
    assert_equal 12, value.Offset
    assert_same FORMAT::Vector3, value.VertexElementFormat
    assert_same USAGE::TextureCoordinate, value.VertexElementUsage
    assert_equal 7, value.UsageIndex

    assert_raises(ArgumentError) { VERTEX.new(0) }
    assert_raises(ArgumentError) { VERTEX.new(0, FORMAT::Single, USAGE::Position) }
    assert_raises(ArgumentError) { VERTEX.new(0, FORMAT::Single, USAGE::Position, 0, 1) }
  end

  def test_constructor_and_setters_validate_exact_int32_and_enum_domains
    assert_raises(TypeError) { VERTEX.new(0.0, FORMAT::Single, USAGE::Position, 0) }
    assert_raises(RangeError) { VERTEX.new(INT32_MIN - 1, FORMAT::Single, USAGE::Position, 0) }
    assert_raises(RangeError) { VERTEX.new(0, FORMAT::Single, USAGE::Position, INT32_MAX + 1) }
    assert_raises(TypeError) { VERTEX.new(0, USAGE::Position, USAGE::Position, 0) }
    assert_raises(TypeError) { VERTEX.new(0, FORMAT::Single, FORMAT::Single, 0) }
    assert_raises(RangeError) { VERTEX.new(0, 12, USAGE::Position, 0) }
    assert_raises(RangeError) { VERTEX.new(0, FORMAT::Single, 13, 0) }

    value = VERTEX.new
    assert_raises(TypeError) { value.Offset = nil }
    assert_raises(RangeError) { value.Offset = INT32_MAX + 1 }
    assert_raises(TypeError) { value.UsageIndex = 1.0 }
    assert_raises(RangeError) { value.UsageIndex = INT32_MIN - 1 }
    assert_raises(TypeError) { value.VertexElementFormat = USAGE::Position }
    assert_raises(RangeError) { value.VertexElementFormat = -1 }
    assert_raises(TypeError) { value.VertexElementUsage = FORMAT::Single }
    assert_raises(RangeError) { value.VertexElementUsage = 99 }
  end

  def test_raw_int32_boundaries_are_stored_without_clamp_or_semantic_validation
    [0, 1, -1, INT32_MIN, INT32_MAX].each do |number|
      value = VERTEX.new(number, FORMAT::HalfVector4, USAGE::TessellateFactor, number)
      assert_equal number, value.Offset
      assert_equal number, value.UsageIndex

      value.Offset = number
      value.UsageIndex = number
      assert_equal number, value.Offset
      assert_equal number, value.UsageIndex
    end

    value = VERTEX.new
    value.VertexElementFormat = 11
    value.VertexElementUsage = 12
    assert_same FORMAT::HalfVector4, value.VertexElementFormat
    assert_same USAGE::TessellateFactor, value.VertexElementUsage
  end

  def test_dup_and_clone_are_independent_mutable_value_objects
    original = VERTEX.new(12, FORMAT::Vector3, USAGE::TextureCoordinate, 7)
    duplicate = original.dup
    clone = original.clone

    [duplicate, clone].each do |copy|
      refute_same original, copy
      assert_equal original, copy
      copy.Offset = -16
      copy.VertexElementFormat = FORMAT::HalfVector4
      copy.VertexElementUsage = USAGE::Tangent
      copy.UsageIndex = -3
    end

    assert_equal 12, original.Offset
    assert_same FORMAT::Vector3, original.VertexElementFormat
    assert_same USAGE::TextureCoordinate, original.VertexElementUsage
    assert_equal 7, original.UsageIndex
    assert_equal VERTEX.new(-16, FORMAT::HalfVector4, USAGE::Tangent, -3), duplicate
    assert_equal duplicate, clone
  end

  def test_equals_object_and_operators_compare_all_four_fields
    value = VERTEX.new(12, FORMAT::Vector3, USAGE::TextureCoordinate, 7)
    equal = value.dup
    assert value.Equals(equal)
    assert value == equal
    refute value != equal
    refute value.Equals(nil)
    refute value.Equals(Object.new)
    refute value.Equals("vertex")

    differences = [
      VERTEX.new(13, FORMAT::Vector3, USAGE::TextureCoordinate, 7),
      VERTEX.new(12, FORMAT::Vector4, USAGE::TextureCoordinate, 7),
      VERTEX.new(12, FORMAT::Vector3, USAGE::Normal, 7),
      VERTEX.new(12, FORMAT::Vector3, USAGE::TextureCoordinate, 8)
    ]
    differences.each do |different|
      refute value.Equals(different)
      refute value == different
      assert value != different
    end
  end

  def test_get_hash_code_matches_xna_smart_memory_hash
    fixtures = [
      [VERTEX.new, INT32_MAX],
      [VERTEX.new(12, FORMAT::Vector3, USAGE::TextureCoordinate, 7), 11],
      [VERTEX.new(-16, FORMAT::HalfVector4, USAGE::Tangent, -3), 3],
      [VERTEX.new(INT32_MIN, FORMAT::HalfVector4, USAGE::TessellateFactor, INT32_MAX), -8],
      [VERTEX.new(1, FORMAT::Vector3, USAGE::Normal, 0), INT32_MAX],
      [VERTEX.new(INT32_MAX, FORMAT::Single, USAGE::Position, INT32_MIN), -1]
    ]
    fixtures.each do |value, expected|
      assert_equal expected, value.GetHashCode
      assert_equal expected, value.hash
    end
  end

  def test_to_string_matches_exact_xna_labels_order_and_formatting
    fixtures = {
      VERTEX.new => "{Offset:0 Format:Single Usage:Position UsageIndex:0}",
      VERTEX.new(12, FORMAT::Vector3, USAGE::TextureCoordinate, 7) =>
        "{Offset:12 Format:Vector3 Usage:TextureCoordinate UsageIndex:7}",
      VERTEX.new(-16, FORMAT::HalfVector4, USAGE::Tangent, -3) =>
        "{Offset:-16 Format:HalfVector4 Usage:Tangent UsageIndex:-3}",
      VERTEX.new(INT32_MIN, FORMAT::HalfVector4, USAGE::TessellateFactor, INT32_MAX) =>
        "{Offset:-2147483648 Format:HalfVector4 Usage:TessellateFactor UsageIndex:2147483647}"
    }
    fixtures.each do |value, expected|
      assert_equal expected, value.ToString
      assert_equal expected, value.to_s
    end
  end

  def test_public_surface_has_no_backing_fields_aliases_or_future_vertex_helpers
    value = VERTEX.new
    %i[offset offset= format format= usage usage= Format Format= Usage Usage=
       SizeInBytes ComponentCount Stride ElementSize VertexDeclaration].each do |name|
      refute_respond_to value, name
    end
    assert_empty VERTEX.constants(false)
  end
end
