# frozen_string_literal: true

require_relative "geometry_test_helper"

class RayGeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_nullable_intersections
    box = F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1))
    assert_equal 1.0, F::Ray.new(F::Vector3.new(-2, 0, 0), F::Vector3.UnitX).Intersects(box)
    assert_nil F::Ray.new(F::Vector3.new(2, 0, 0), F::Vector3.UnitY).Intersects(box)
    sphere = F::BoundingSphere.new(F::Vector3.Zero, 1)
    assert_equal 2.0, F::Ray.new(F::Vector3.new(-2, 1, 0), F::Vector3.UnitX).Intersects(sphere)
    plane = F::Plane.new(F::Vector3.UnitX, -1)
    assert_nil F::Ray.new(F::Vector3.new(2, 0, 0), F::Vector3.UnitX).Intersects(plane)
  end

  def test_position_and_direction_are_copied
    position = F::Vector3.new(1, 2, 3); ray = F::Ray.new(position, F::Vector3.UnitX)
    position.X = 9
    assert_equal 1.0, ray.Position.X
    fetched = ray.Position; fetched.X = 8
    assert_equal 1.0, ray.Position.X
  end
end
