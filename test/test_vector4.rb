# frozen_string_literal: true

require_relative "geometry_test_helper"

class Vector4GeometryTest < Minitest::Test
  include GeometryTestHelper

  def test_constructors_and_transforms
    assert_equal F::Vector4.new(1, 2, 3, 4), F::Vector4.new(F::Vector2.new(1, 2), 3, 4)
    assert_equal F::Vector4.new(1, 2, 3, 4), F::Vector4.new(F::Vector3.new(1, 2, 3), 4)
    assert_equal F::Vector4.new(5, 7, 9, 1), F::Vector4.Transform(F::Vector4.new(1, 2, 3, 1), F::Matrix.CreateTranslation(4, 5, 6))
    assert_equal 20.0, F::Vector4.Dot(F::Vector4.new(1, 2, 3, 4), F::Vector4.new(4, 3, 2, 1))
  end

  def test_array_transform_is_caller_owned
    source = [F::Vector4.One]
    destination = [nil]
    assert_nil F::Vector4.Transform(source, F::Matrix.CreateScale(2), destination)
    assert_equal F::Vector4.new(2, 2, 2, 1), destination[0]
    refute_same source[0], destination[0]
  end
end
