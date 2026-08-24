# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "../lib/cna"

class RectangleTest < Minitest::Test
  F = Microsoft::Xna::Framework
  Rectangle = F::Rectangle
  Point = F::Point
  INT_MIN = -2_147_483_648
  INT_MAX = 2_147_483_647

  def components(value) = [value.X, value.Y, value.Width, value.Height]

  def test_constructor_fields_properties_and_value_copies
    assert_equal [0, 0, 0, 0], components(Rectangle.new)
    rectangle = Rectangle.new(2, 3, 4, 5)
    assert_equal [2, 6, 3, 8], [rectangle.Left, rectangle.Right, rectangle.Top, rectangle.Bottom]
    assert_equal [4, 5], [rectangle.Center.X, rectangle.Center.Y]

    location = rectangle.Location
    location.X = 100
    assert_equal 2, rectangle.X
    rectangle.Location = Point.new(7, 8)
    assert_equal [7, 8], [rectangle.X, rectangle.Y]

    copy = rectangle.dup
    cloned = rectangle.clone
    copy.X = 9
    cloned.Y = 10
    assert_equal [7, 8, 4, 5], components(rectangle)
    refute_same Rectangle.Empty, Rectangle.Empty
    assert Rectangle.Empty.IsEmpty
    refute Rectangle.new(0, 0, 0, 1).IsEmpty
    refute Rectangle.new(1, 0, 0, 0).IsEmpty
  end

  def test_center_truncates_negative_halves_toward_zero_and_wraps
    assert_equal [-1, -1], begin
      center = Rectangle.new(-2, -2, 3, 3).Center
      [center.X, center.Y]
    end
    assert_equal [0, 0], begin
      center = Rectangle.new(0, 0, -1, -1).Center
      [center.X, center.Y]
    end
    assert_equal INT_MIN, Rectangle.new(INT_MAX, 0, 2, 0).Center.X
    assert_equal INT_MAX, Rectangle.new(INT_MIN, 0, -2, 0).Center.X
  end

  def test_right_bottom_offset_and_inflate_wrap_int32
    rectangle = Rectangle.new(INT_MAX, INT_MIN, 1, -1)
    assert_equal INT_MIN, rectangle.Right
    assert_equal INT_MAX, rectangle.Bottom
    rectangle.Offset(1, -1)
    assert_equal [INT_MIN, INT_MAX], [rectangle.X, rectangle.Y]
    rectangle.Offset(Point.new(-1, 1))
    assert_equal [INT_MAX, INT_MIN], [rectangle.X, rectangle.Y]

    inflated = Rectangle.new(INT_MIN, INT_MAX, INT_MAX, INT_MIN)
    inflated.Inflate(1, -1)
    assert_equal [INT_MAX, INT_MIN, INT_MIN + 1, INT_MAX - 1], components(inflated)

    multiplied = Rectangle.new(0, 0, 0, 0)
    multiplied.Inflate(INT_MAX, INT_MIN)
    assert_equal [-INT_MAX, INT_MIN, -2, 0], components(multiplied)
  end

  def test_point_containment_is_left_top_inclusive_and_right_bottom_exclusive
    rectangle = Rectangle.new(2, 3, 4, 5)
    assert rectangle.Contains(2, 3)
    assert rectangle.Contains(Point.new(2, 3))
    assert rectangle.Contains(5, 7)
    refute rectangle.Contains(6, 3)
    refute rectangle.Contains(2, 8)
    refute rectangle.Contains(6, 8)
    refute rectangle.Contains(1, 3)
    refute rectangle.Contains(2, 2)
    refute Rectangle.new(2, 3, 0, 5).Contains(2, 3)
    refute Rectangle.new(2, 3, 5, 0).Contains(2, 3)
    refute Rectangle.new(2, 3, -4, -5).Contains(2, 3)
    refute Rectangle.Empty.Contains(0, 0)
  end

  def test_rectangle_containment_preserves_degenerate_and_negative_semantics
    outer = Rectangle.new(0, 0, 10, 10)
    assert outer.Contains(Rectangle.new(0, 0, 10, 10))
    assert outer.Contains(Rectangle.new(10, 10, 0, 0))
    assert outer.Contains(Rectangle.new(2, 3, 0, 0))
    refute outer.Contains(Rectangle.new(9, 9, 2, 2))
    assert outer.Contains(Rectangle.new(5, 5, -2, -2))
    assert Rectangle.Empty.Contains(Rectangle.Empty)
  end

  def test_intersects_boundaries_degenerate_and_one_unit_overlap
    base = Rectangle.new(0, 0, 10, 10)
    refute base.Intersects(Rectangle.new(10, 0, 5, 5))
    refute base.Intersects(Rectangle.new(0, 10, 5, 5))
    assert base.Intersects(Rectangle.new(9, 9, 5, 5))
    assert base.Intersects(Rectangle.new(0, 0, 10, 10))
    # XNA applies only its four edge comparisons; interior zero/negative
    # extents can therefore report true and are not normalized away.
    assert base.Intersects(Rectangle.new(5, 5, 0, 0))
    assert base.Intersects(Rectangle.new(5, 5, -1, -1))
    refute Rectangle.Empty.Intersects(Rectangle.Empty)
  end

  def test_intersect_exact_empty_and_overflow_behavior
    assert_equal [5, 0, 5, 5], components(Rectangle.Intersect(
      Rectangle.new(0, 0, 10, 10), Rectangle.new(5, -5, 10, 10)
    ))
    assert_equal [0, 0, 0, 0], components(Rectangle.Intersect(
      Rectangle.new(0, 0, 10, 10), Rectangle.new(10, 0, 5, 5)
    ))
    assert_equal [0, 0, 0, 0], components(Rectangle.Intersect(
      Rectangle.new(0, 0, 10, 10), Rectangle.new(20, 20, 0, 0)
    ))
    assert_equal [2, 2, 3, 3], components(Rectangle.Intersect(
      Rectangle.new(0, 0, 10, 10), Rectangle.new(2, 2, 3, 3)
    ))
    assert_equal [0, 0, 0, 0], components(Rectangle.Intersect(
      Rectangle.new(INT_MAX, 0, 2, 1), Rectangle.new(INT_MIN, 0, 1, 1)
    ))
  end

  def test_union_wraps_derived_width_and_height
    assert_equal [0, -5, 15, 15], components(Rectangle.Union(
      Rectangle.new(0, 0, 10, 10), Rectangle.new(5, -5, 10, 10)
    ))
    assert_equal [0, 0, 10, 10], components(Rectangle.Union(
      Rectangle.new(0, 0, 10, 10), Rectangle.new(2, 2, 3, 3)
    ))
    assert_equal [0, 0, 0, 0], components(Rectangle.Union(Rectangle.Empty, Rectangle.Empty))
    assert_equal [INT_MIN, 0, 1, 1], components(Rectangle.Union(
      Rectangle.new(INT_MAX, 0, 2, 1), Rectangle.new(INT_MIN, 0, 1, 1)
    ))
    assert_equal [INT_MIN, INT_MIN, -1, -1], components(Rectangle.Union(
      Rectangle.new(INT_MIN, INT_MIN, 0, 0), Rectangle.new(INT_MAX, INT_MAX, 0, 0)
    ))
  end

  def test_equality_hash_string_and_invalid_dispatch
    value = Rectangle.new(INT_MAX, INT_MAX, 1, 1)
    assert value.Equals(Rectangle.new(INT_MAX, INT_MAX, 1, 1))
    refute value.Equals(Rectangle.new(INT_MAX, INT_MAX, 1, 0))
    refute value.Equals(Object.new)
    assert_equal 0, value.GetHashCode
    assert_equal "{X:2147483647 Y:2147483647 Width:1 Height:1}", value.ToString
    assert_raises(TypeError) { Rectangle.new(0, 0, 1, 1).Intersects(Point.Zero) }
    assert_raises(ArgumentError) { Rectangle.new(0, 0, 1, 1).Contains("point") }
    assert_raises(RangeError) { Rectangle.new(INT_MAX + 1, 0, 0, 0) }
  end

  def test_five_ref_out_identities_are_retained_and_collapse_to_runtime_shapes
    contract = JSON.parse(File.read(File.expand_path("../tools/api_compat/signatures.json", __dir__)))
    type = contract.fetch("types").find { |candidate| candidate["name"] == "Microsoft.Xna.Framework.Rectangle" }
    ref_out = type.fetch("members").select do |member|
      member.fetch("parameters", []).any? { |parameter| parameter["ref"] || parameter["out"] }
    end
    assert_equal 5, ref_out.length
    assert_equal({"Contains" => 2, "Intersects" => 1, "Intersect" => 1, "Union" => 1}, ref_out.group_by { |member| member["name"] }.transform_values(&:length))

    rectangle = Rectangle.new(0, 0, 10, 10)
    assert rectangle.Contains(Point.new(0, 0))
    assert rectangle.Contains(Rectangle.new(1, 1, 2, 2))
    assert rectangle.Intersects(Rectangle.new(9, 9, 2, 2))
    assert_equal [9, 9, 1, 1], components(Rectangle.Intersect(rectangle, Rectangle.new(9, 9, 2, 2)))
    assert_equal [0, 0, 11, 11], components(Rectangle.Union(rectangle, Rectangle.new(9, 9, 2, 2)))
  end
end
