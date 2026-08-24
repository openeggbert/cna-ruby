# frozen_string_literal: true

require_relative "geometry_test_helper"

class BoundingFrustumGeometryTest < Minitest::Test
  include GeometryTestHelper

  def setup
    @frustum = F::BoundingFrustum.new(F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver2, 1, 1, 10))
  end

  def test_exact_corner_order_and_copy_boundaries
    expected = [
      [-1, 1, -1], [1, 1, -1], [1, -1, -1], [-1, -1, -1],
      [-10, 10, -10], [10, 10, -10], [10, -10, -10], [-10, -10, -10]
    ]
    expected.zip(@frustum.GetCorners).each { |components, actual| assert_vector F::Vector3.new(*components), actual, delta: 0.00002 }
    destination = Array.new(8); assert_nil @frustum.GetCorners(destination)
    assert_equal @frustum.GetCorners, destination
    matrix = @frustum.Matrix; matrix.M11 = 99
    refute_equal 99, @frustum.Matrix.M11
  end

  def test_planes_contains_intersections_and_equality
    assert_equal F::Plane.new(F::Vector3.Backward, 1), @frustum.Near
    assert_equal F::ContainmentType::Contains, @frustum.Contains(F::Vector3.new(0, 0, -2))
    assert_equal F::ContainmentType::Disjoint, @frustum.Contains(F::Vector3.new(100, 0, -2))
    inside = F::BoundingBox.new(F::Vector3.new(-0.25, -0.25, -2.25), F::Vector3.new(0.25, 0.25, -1.75))
    outside = F::BoundingBox.new(F::Vector3.new(100), F::Vector3.new(101))
    assert @frustum.Intersects(inside)
    refute @frustum.Intersects(outside)
    assert_equal 1.0, @frustum.Intersects(F::Ray.new(F::Vector3.Zero, F::Vector3.Forward))
    same = F::BoundingFrustum.new(@frustum.Matrix)
    assert_equal @frustum, same
    assert_equal F::ContainmentType::Contains, @frustum.Contains(same)
  end
end
