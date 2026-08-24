# frozen_string_literal: true

require_relative "geometry_test_helper"

class BoundingBoxGeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_corners_creation_containment_and_merge
    box = F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1))
    corners = box.GetCorners
    assert_equal 8, corners.length
    destination = Array.new(8); assert_nil box.GetCorners(destination); assert_equal corners, destination
    assert_equal box, F::BoundingBox.CreateFromPoints(corners)
    assert_equal F::ContainmentType::Contains, box.Contains(F::Vector3.new(1, 1, 1))
    assert_equal F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(2)), F::BoundingBox.CreateMerged(box, F::BoundingBox.new(F::Vector3.new(1), F::Vector3.new(2)))
  end

  def test_field_copy_and_tangent_sphere
    box = F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1))
    minimum = box.Min; minimum.X = -9
    assert_equal(-1.0, box.Min.X)
    assert box.Intersects(F::BoundingSphere.new(F::Vector3.new(2, 0, 0), 1))
  end
end
