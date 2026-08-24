# frozen_string_literal: true

require_relative "geometry_test_helper"

class PlaneGeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_constructors_normalize_dots_and_transform
    plane = F::Plane.new(F::Vector3.new(0, 2, 0), -4)
    assert_equal F::Plane.new(F::Vector3.Up, -2), F::Plane.Normalize(plane)
    assert_equal 0.0, plane.Dot(F::Vector4.new(0, 2, 0, 1))
    assert_equal F::Plane.new(1, 2, 3, 4), F::Plane.new(F::Vector4.new(1, 2, 3, 4))
    translated = F::Plane.Transform(F::Plane.new(F::Vector3.UnitX, 0), F::Matrix.CreateTranslation(2, 0, 0))
    assert_equal(-2.0, translated.D)
  end

  def test_value_boundaries_and_classification
    plane = F::Plane.new(F::Vector3.UnitY, 0)
    normal = plane.Normal; normal.Y = 9
    assert_equal F::Vector3.UnitY, plane.Normal
    box = F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1))
    assert_equal F::PlaneIntersectionType::Intersecting, plane.Intersects(box)
  end
end
