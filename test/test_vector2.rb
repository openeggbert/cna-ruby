# frozen_string_literal: true

require_relative "geometry_test_helper"

class Vector2GeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_complete_math_and_ref_out_projection
    value = F::Vector2.new(3, 4)
    assert_equal 5.0, value.Length
    assert_equal F::Vector2.new(1, 1), F::Vector2.Reflect(F::Vector2.new(1, -1), F::Vector2.UnitY)
    assert_equal F::Vector2.new(1, 1), F::Vector2.Barycentric(F::Vector2.Zero, F::Vector2.new(2, 0), F::Vector2.new(0, 4), 0.5, 0.25)
    assert_equal F::Vector2.new(4, 6), F::Vector2.Transform(F::Vector2.new(1, 2), F::Matrix.CreateTranslation(3, 4, 9))
    assert_equal F::Vector2.new(1, 2), F::Vector2.TransformNormal(F::Vector2.new(1, 2), F::Matrix.CreateTranslation(3, 4, 9))
  end

  def test_array_overlap_and_copy_boundaries
    values = [F::Vector2.new(1, 2), F::Vector2.new(3, 4), F::Vector2.new(5, 6)]
    assert_nil F::Vector2.Transform(values, 0, F::Matrix.CreateTranslation(1, 2, 0), values, 1, 2)
    assert_equal [F::Vector2.new(1, 2), F::Vector2.new(2, 4), F::Vector2.new(3, 6)], values
    values[1].X = 99
    assert_equal 1.0, values[0].X
    assert_raises(IndexError) { F::Vector2.Transform(values, -1, F::Matrix.Identity, values, 0, 1) }
  end
end
