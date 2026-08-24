# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class ValuesTest < Minitest::Test
  F = Microsoft::Xna::Framework

  def test_float32_vector_and_copy_semantics
    value = F::Vector2.new(3, 4)
    assert_equal 5.0, value.Length
    normalized = F::Vector2.Normalize(value)
    assert_equal [0.6000000238418579, 0.800000011920929], [normalized.X, normalized.Y]
    refute_same F::Vector2.Zero, F::Vector2.Zero
    refute_same value, value.dup
  end

  def test_rectangle_semantics
    rectangle = F::Rectangle.new(0, 0, 10, 20)
    assert rectangle.Contains(0, 0)
    refute rectangle.Contains(10, 20)
    assert_equal [5, 10], [rectangle.Center.X, rectangle.Center.Y]
    assert_equal [5, 0, 5, 5], begin
      value = F::Rectangle.Intersect(rectangle, F::Rectangle.new(5, -5, 10, 10))
      [value.X, value.Y, value.Width, value.Height]
    end
  end

  def test_color_and_enum_validation
    color = F::Color.new(300, -2, 1, 999)
    assert_equal [255, 0, 1, 255], [color.R, color.G, color.B, color.A]
    assert_equal 67_305_985, F::Color.new(1, 2, 3, 4).PackedValue
    assert_raises(TypeError) { Microsoft::Xna::Framework::Input::Keys.coerce(Object.new) }
    assert_raises(RangeError) { Microsoft::Xna::Framework::Input::Keys.coerce(7) }
  end
end
