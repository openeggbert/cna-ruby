# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/microsoft/xna/framework/graphics"

class ViewportTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = F::Graphics
  N = CNA::Runtime::Numeric

  def test_project_identity_origin_y_inversion_and_nondefault_depth_are_exact
    viewport = qualified_viewport
    assert_vector_bits [0x437d6000, 0x42e18000, 0x3f300000],
                       viewport.Project(F::Vector3.new(-0.25, 0.5, 0.75), identity, identity, identity)

    expected_depth = {
      0.0 => 0x3e4ccccd,
      1.0 => 0x3f59999a,
      0.3 => 0x3eca3d71,
      1.5 => 0x3f966667
    }
    expected_depth.each do |depth, bits|
      result = viewport.Project(F::Vector3.new(0.125, -0.25, depth), identity, identity, identity)
      assert_vector_bits [0x43bac800, 0x43923000, bits], result
    end
  end

  def test_nontrivial_project_and_direct_unproject_match_windows_xna_bits
    viewport = qualified_viewport
    world, view, projection = nontrivial_matrices
    object_source = F::Vector3.new(0.375, -1.25, 2.5)

    assert_vector_bits [0x44420eed, 0x43942fd4, 0x3f32c1c2],
                       viewport.Project(object_source, projection, view, world)
    assert_vector_bits [0xc01f32f5, 0xbef8831c, 0x3f55d950],
                       viewport.Unproject(F::Vector3.new(333.25, 211.5, 0.625), projection, view, world)

    left = F::Matrix.Multiply(F::Matrix.Multiply(world, view), projection)
    right = F::Matrix.Multiply(world, F::Matrix.Multiply(view, projection))
    refute_equal vector_values(F::Vector3.Transform(object_source, left)).map { |value| N.f32_bits(value) },
                 vector_values(F::Vector3.Transform(object_source, right)).map { |value| N.f32_bits(value) }
  end

  def test_w_branch_uses_single_min_subnormal_tolerance
    viewport = G::Viewport.new(17, 23, 311, 197)
    source = F::Vector3.new(0.25, -0.375, 0.625)
    cases = {
      0x3f800000 => [0x43536000, 0x431e7000, 0x3f200000],
      0x3f7fffff => [0x43536000, 0x431e7000, 0x3f200001],
      0x3f800001 => [0x43536000, 0x431e7000, 0x3f1fffff],
      0x40000000 => [0x433ff000, 0x430bf800, 0x3ea00000]
    }
    cases.each do |w_bits, expected|
      assert_vector_bits expected, viewport.Project(source, identity, identity, matrix_with_w(w_bits))
    end

    screen = F::Vector3.new(211.375, 158.4375, 0.625)
    inverse_cases = {
      0x3f800000 => [0x3e800000, 0xbec00000, 0x3f200000],
      0x3f7fffff => [0x3e7ffffe, 0xbebfffff, 0x3f1fffff],
      0x3f800001 => [0x3e800001, 0xbec00002, 0x3f200001],
      0x3f000000 => [0x3e000000, 0xbe400000, 0x3ea00000]
    }
    inverse_cases.each do |w_bits, expected|
      assert_vector_bits expected, viewport.Unproject(screen, identity, identity, matrix_with_w(w_bits))
    end
  end

  def test_unproject_identity_and_round_trips_retain_direct_reference_results
    viewport = qualified_viewport
    assert_vector_bits [0xbe800000, 0x3f000000, 0x3f400000],
                       viewport.Unproject(F::Vector3.new(253.375, 112.75, 0.6875), identity, identity, identity)

    world, view, projection = nontrivial_matrices
    object_source = F::Vector3.new(0.375, -1.25, 2.5)
    projected = viewport.Project(object_source, projection, view, world)
    assert_vector_bits [0x3ec00003, 0xbfa00001, 0x40200001],
                       viewport.Unproject(projected, projection, view, world)

    screen_source = F::Vector3.new(411.75, 83.125, 0.42)
    unprojected = viewport.Unproject(screen_source, projection, view, world)
    assert_vector_bits [0x43cddffe, 0x42a63ffc, 0x3ed70a3d],
                       viewport.Project(unprojected, projection, view, world)
  end

  def test_negative_extents_reversed_depth_zero_divisions_and_singular_matrix_follow_single_arithmetic
    viewport = G::Viewport.new(-31, 47, -257, -129)
    viewport.MinDepth = 0.8
    viewport.MaxDepth = -0.3
    assert_vector_bits [0xc2a4cccc, 0x40a26666, 0xbf133334],
                       viewport.Project(F::Vector3.new(-0.6, 0.35, 1.25), identity, identity, identity)
    assert_vector_bits [0xbee718e7, 0x3dc6731a, 0x3f1d1746],
                       viewport.Unproject(F::Vector3.new(-101.5, -11.25, 0.125), identity, identity, identity)

    zero = G::Viewport.new(5, -9, 0, 0)
    assert_all_nan zero.Unproject(F::Vector3.new(5.0, -9.0, 0.5), identity, identity, identity)
    assert_vector_bits [0xffc00000, 0xffc00000, 0xffc00000],
                       G::Viewport.new(5, -9, 0, 17).Unproject(F::Vector3.new(6.0, -4.0, 0.5), identity, identity, identity)
    assert_vector_bits [0xffc00000, 0xffc00000, 0xffc00000],
                       G::Viewport.new(5, -9, 19, 0).Unproject(F::Vector3.new(7.0, -8.0, 0.5), identity, identity, identity)

    zero.MinDepth = zero.MaxDepth = 0.25
    assert_all_nan zero.Unproject(F::Vector3.new(6.0, -8.0, 0.25), identity, identity, identity)
    assert_vector_bits [0xffc00000, 0xffc00000, 0xffc00000],
                       qualified_viewport.Unproject(F::Vector3.new(101.0, 77.0, 0.4), F::Matrix.new, identity, identity)
  end

  def test_nonfinite_values_propagate_without_validation_or_ruby_math_exceptions
    viewport = qualified_viewport
    projected = viewport.Project(F::Vector3.new(Float::NAN, Float::INFINITY, -Float::INFINITY),
                                 identity, identity, identity)
    assert_vector_bits [0xffc00000, 0x7fc00000, 0xffc00000], projected

    unprojected = viewport.Unproject(F::Vector3.new(Float::INFINITY, Float::NAN, -Float::INFINITY),
                                    identity, identity, identity)
    assert_all_nan unprojected
  end

  def test_inputs_are_not_mutated_and_results_are_independent_values
    viewport = qualified_viewport
    source = F::Vector3.new(0.375, -1.25, 2.5)
    world, view, projection = nontrivial_matrices
    snapshots = [vector_values(source), matrix_values(projection), matrix_values(view), matrix_values(world)]

    first = viewport.Project(source, projection, view, world)
    second = viewport.Project(source, projection, view, world)
    viewport.Unproject(first, projection, view, world)
    assert_equal snapshots, [vector_values(source), matrix_values(projection), matrix_values(view), matrix_values(world)]
    refute_same source, first
    refute_same first, second
    old_second_x = second.X
    first.X = -99.0
    assert_equal old_second_x, second.X
    assert_equal 13, viewport.X
  end

  def test_title_safe_area_is_read_only_bounds_copy_for_all_windows_reference_cases
    cases = [[13, -7, 641, 479], [-11, 23, 5, 7], [3, 4, 0, 1], [7, -8, -9, -10]]
    cases.each do |values|
      viewport = G::Viewport.new(*values)
      first = viewport.TitleSafeArea
      second = viewport.TitleSafeArea
      assert_equal values, [first.X, first.Y, first.Width, first.Height]
      refute_same first, second
      first.X = 123
      assert_equal values, [viewport.X, viewport.Y, viewport.Width, viewport.Height]
      assert_equal values, [second.X, second.Y, second.Width, second.Height]
    end
    refute_includes G::Viewport.public_instance_methods(false), :TitleSafeArea=
  end

  def test_exact_method_shapes_types_and_managed_only_surface
    viewport = G::Viewport.new(0, 0, 1, 1)
    assert_equal 4, viewport.method(:Project).arity
    assert_equal 4, viewport.method(:Unproject).arity
    assert_raises(ArgumentError) { viewport.Project(F::Vector3.Zero, identity, identity) }
    assert_raises(ArgumentError) { viewport.Unproject(F::Vector3.Zero, identity, identity, identity, identity) }

    wrong_values = [nil, [], {}, Object.new]
    wrong_values.each do |wrong|
      assert_raises(TypeError) { viewport.Project(wrong, identity, identity, identity) }
      assert_raises(TypeError) { viewport.Project(F::Vector3.Zero, wrong, identity, identity) }
      assert_raises(TypeError) { viewport.Project(F::Vector3.Zero, identity, wrong, identity) }
      assert_raises(TypeError) { viewport.Project(F::Vector3.Zero, identity, identity, wrong) }
      assert_raises(TypeError) { viewport.Unproject(wrong, identity, identity, identity) }
      assert_raises(TypeError) { viewport.Unproject(F::Vector3.Zero, wrong, identity, identity) }
      assert_raises(TypeError) { viewport.Unproject(F::Vector3.Zero, identity, wrong, identity) }
      assert_raises(TypeError) { viewport.Unproject(F::Vector3.Zero, identity, identity, wrong) }
    end

    %i[project unproject title_safe_area].each do |name|
      refute_includes G::Viewport.public_instance_methods(false), name
    end
    refute_includes G::GraphicsDevice.public_instance_methods(false), :Viewport=

    previous_library = ENV.delete("CNA_NATIVE_LIBRARY")
    CNA::Native.stub(:library, -> { raise "Viewport crossed the native boundary" }) do
      managed = G::Viewport.new(3, 4, 5, 6)
      managed.Project(F::Vector3.Zero, identity, identity, identity)
      managed.Unproject(F::Vector3.Zero, identity, identity, identity)
      managed.TitleSafeArea
    end
  ensure
    ENV["CNA_NATIVE_LIBRARY"] = previous_library if previous_library
  end

  private

  def assert_vector_bits(expected, actual)
    assert_instance_of F::Vector3, actual
    assert_equal expected, vector_values(actual).map { |value| N.f32_bits(value) }
  end

  def assert_all_nan(actual)
    assert_instance_of F::Vector3, actual
    vector_values(actual).each { |value| assert_predicate value, :nan? }
  end

  def vector_values(value) = [value.X, value.Y, value.Z]

  def matrix_values(value)
    (1..4).flat_map { |row| (1..4).map { |column| value.public_send("M#{row}#{column}") } }
  end

  def identity = F::Matrix.Identity

  def qualified_viewport
    G::Viewport.new(13, -7, 641, 479).tap do |viewport|
      viewport.MinDepth = 0.2
      viewport.MaxDepth = 0.85
    end
  end

  def matrix_with_w(bits)
    identity.tap { |matrix| matrix.M44 = N.f32_from_bits(bits) }
  end

  def nontrivial_matrices
    world = F::Matrix.new(
      1.25, -0.375, 0.5, 0.0625,
      0.2, 0.875, -0.45, -0.03125,
      -0.15, 0.3, 1.1, 0.125,
      3.5, -2.25, 4.75, 1.0
    )
    view = F::Matrix.new(
      0.9, 0.1, -0.2, 0.015625,
      -0.05, 1.05, 0.125, -0.0078125,
      0.225, -0.175, 0.8, 0.03125,
      -1.5, 2.75, -3.25, 1.0
    )
    projection = F::Matrix.new(
      1.1, -0.075, 0.04, 0.2,
      0.125, 0.95, -0.06, -0.1,
      -0.035, 0.08, 1.2, 0.3,
      0.15, -0.2, 0.25, 0.9
    )
    [world, view, projection]
  end
end
