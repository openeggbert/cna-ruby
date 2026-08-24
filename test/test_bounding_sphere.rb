# frozen_string_literal: true

require_relative "geometry_test_helper"

class BoundingSphereGeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_creation_merge_surface_and_transform
    sphere = F::BoundingSphere.new(F::Vector3.Zero, 1)
    assert_equal F::ContainmentType::Disjoint, sphere.Contains(F::Vector3.UnitX)
    refute sphere.Intersects(F::BoundingSphere.new(F::Vector3.new(2, 0, 0), 1))
    assert_equal F::BoundingSphere.new(F::Vector3.Zero, 2), F::BoundingSphere.CreateFromPoints([F::Vector3.new(-2, 0, 0), F::Vector3.new(2, 0, 0), F::Vector3.Zero])
    assert_equal F::BoundingSphere.new(F::Vector3.new(1.5, 0, 0), 2.5), F::BoundingSphere.CreateMerged(sphere, F::BoundingSphere.new(F::Vector3.new(3, 0, 0), 1))
    transformed = sphere.Transform(F::Matrix.CreateScale(2, 3, 4) * F::Matrix.CreateTranslation(5, 6, 7))
    assert_equal F::Vector3.new(5, 6, 7), transformed.Center
    assert_equal 4.0, transformed.Radius
  end

  def test_negative_radius_is_rejected
    assert_raises(ArgumentError) { F::BoundingSphere.new(F::Vector3.Zero, -1) }
  end
end
