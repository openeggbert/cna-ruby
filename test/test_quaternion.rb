# frozen_string_literal: true

require_relative "geometry_test_helper"

class QuaternionGeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_creation_multiplication_order_and_matrix_round_trip
    first = F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitX, 0.2)
    second = F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, 0.4)
    assert_equal second * first, F::Quaternion.Concatenate(first, second)
    rotation = F::Matrix.CreateRotationY(0.7)
    assert_matrix_close rotation, F::Matrix.CreateFromQuaternion(F::Quaternion.CreateFromRotationMatrix(rotation))
  end

  def test_slerp_inverse_and_degenerate_normalization
    result = F::Quaternion.Slerp(F::Quaternion.Identity, F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, F::MathHelper::PiOver2), 0.5)
    assert_in_delta 0.38268343, result.Y, 0.000001
    assert_in_delta 0.9238795, result.W, 0.000001
    value = F::Quaternion.new(1, 2, 3, 4)
    product = value * F::Quaternion.Inverse(value)
    assert_vector F::Quaternion.Identity, product
    assert F::Quaternion.Normalize(F::Quaternion.new).X.nan?
  end
end
