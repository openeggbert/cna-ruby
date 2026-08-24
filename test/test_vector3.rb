# frozen_string_literal: true

require_relative "geometry_test_helper"

class Vector3GeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_directions_cross_hash_and_transforms
    assert_equal F::Vector3.new(0, 0, -1), F::Vector3.Forward
    assert_equal F::Vector3.UnitZ, F::Vector3.Cross(F::Vector3.UnitX, F::Vector3.UnitY)
    assert_equal(-1_077_936_128, F::Vector3.new(1, 2, 3).GetHashCode)
    transform = F::Matrix.CreateScale(2, 3, 4) * F::Matrix.CreateTranslation(5, 6, 7)
    assert_equal F::Vector3.new(7, 9, 11), F::Vector3.Transform(F::Vector3.One, transform)
    assert_equal F::Vector3.new(2, 3, 4), F::Vector3.TransformNormal(F::Vector3.One, transform)
  end

  def test_array_forms_and_negative_length
    source = [F::Vector3.Zero, F::Vector3.One]
    destination = [F::Vector3.new(9), F::Vector3.new(9)]
    assert_nil F::Vector3.Transform(source, F::Matrix.CreateTranslation(1, 2, 3), destination)
    assert_equal [F::Vector3.new(1, 2, 3), F::Vector3.new(2, 3, 4)], destination
    assert_nil F::Vector3.Transform(source, 0, F::Matrix.Identity, destination, 0, -1)
  end
end
