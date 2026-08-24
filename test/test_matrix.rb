# frozen_string_literal: true

require_relative "geometry_test_helper"

class MatrixGeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_row_vector_convention_fields_and_inverse
    matrix = F::Matrix.CreateScale(2, 3, 4) * F::Matrix.CreateRotationY(0.25) * F::Matrix.CreateTranslation(5, 6, 7)
    assert_equal F::Vector3.new(5, 6, 7), matrix.Translation
    assert_matrix_close F::Matrix.Identity, matrix * F::Matrix.Invert(matrix), delta: 0.0001
    assert F::Matrix.Invert(F::Matrix.new).instance_variables.all? { |name| F::Matrix.Invert(F::Matrix.new).instance_variable_get(name).nan? }
  end

  def test_direction_setters_decompose_and_transform
    value = F::Matrix.Identity
    value.Right = F::Vector3.new(2, 3, 4); value.Down = F::Vector3.new(5, 6, 7); value.Forward = F::Vector3.new(8, 9, 10)
    assert_equal F::Vector3.new(-5, -6, -7), value.Up
    assert_equal F::Vector3.new(-8, -9, -10), value.Backward
    composed = F::Matrix.CreateScale(2, 3, 4) * F::Matrix.CreateTranslation(5, 6, 7)
    success, scale, rotation, translation = composed.Decompose
    assert success
    assert_equal F::Vector3.new(2, 3, 4), scale
    assert_equal F::Quaternion.Identity, rotation
    assert_equal F::Vector3.new(5, 6, 7), translation
  end

  def test_projection_validation_and_transform_order
    assert_raises(RangeError) { F::Matrix.CreatePerspectiveFieldOfView(0, 1, 0.1, 100) }
    assert_raises(RangeError) { F::Matrix.CreatePerspective(4, 3, 10, 5) }
    view = F::Matrix.CreateLookAt(F::Vector3.new(0, 0, 5), F::Vector3.Zero, F::Vector3.Up)
    assert_equal F::Vector3.new(0, 0, -5), F::Vector3.Transform(F::Vector3.Zero, view)
  end
end
