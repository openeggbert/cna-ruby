# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class CurveTest < Minitest::Test
  F = Microsoft::Xna::Framework
  Curve = F::Curve
  CurveKey = F::CurveKey
  CurveKeyCollection = F::CurveKeyCollection

  def bits(value) = [CNA::Runtime::Numeric.f32(value)].pack("e").unpack1("L<")

  def two_key_curve
    Curve.new.tap do |curve|
      curve.Keys.Add(CurveKey.new(5.0, 0.0))
      curve.Keys.Add(CurveKey.new(7.0, 10.0))
    end
  end

  def test_enum_values_are_exact_typed_and_frozen
    assert_equal [0, 1], [F::CurveContinuity::Smooth, F::CurveContinuity::Step].map(&:to_i)
    assert_equal [0, 1, 2, 3, 4], [
      F::CurveLoopType::Constant, F::CurveLoopType::Cycle, F::CurveLoopType::CycleOffset,
      F::CurveLoopType::Oscillate, F::CurveLoopType::Linear
    ].map(&:to_i)
    assert_equal [0, 1, 2], [F::CurveTangent::Flat, F::CurveTangent::Linear, F::CurveTangent::Smooth].map(&:to_i)
    assert [F::CurveContinuity::Smooth, F::CurveLoopType::Cycle, F::CurveTangent::Smooth].all?(&:frozen?)
    assert_raises(RangeError) { F::CurveContinuity.coerce(2) }
    assert_raises(TypeError) { F::CurveLoopType.coerce(Object.new) }
  end

  def test_curve_key_constructor_defaults_mutability_and_float32_boundaries
    short = CurveKey.new(1.0 / 3.0, 2.0 / 3.0)
    four = CurveKey.new(1, 2, 3, 4)
    five = CurveKey.new(1, 2, 3, 4, F::CurveContinuity::Step)
    assert_equal [0, 0], [short.TangentIn, short.TangentOut]
    assert_same F::CurveContinuity::Smooth, short.Continuity
    assert_same F::CurveContinuity::Smooth, four.Continuity
    assert_same F::CurveContinuity::Step, five.Continuity
    assert_equal 0x3eaa_aaab, bits(short.Position)
    assert_equal 0x3f2a_aaab, bits(short.Value)
    refute_respond_to short, :Position=

    short.Value = 1.0 / 10.0
    short.TangentIn = -1.0 / 3.0
    short.TangentOut = Float::INFINITY
    short.Continuity = 1
    assert_equal [0x3dcc_cccd, 0xbeaa_aaab, 0x7f80_0000],
                 [short.Value, short.TangentIn, short.TangentOut].map { |value| bits(value) }
    assert_same F::CurveContinuity::Step, short.Continuity
    assert_raises(RangeError) { short.Continuity = 3 }
    assert_raises(ArgumentError) { CurveKey.new(1) }
  end

  def test_curve_key_clone_equality_hash_operators_and_reference_semantics
    key = CurveKey.new(1, 2, 3, 4, F::CurveContinuity::Step)
    clone = key.Clone
    refute_same key, clone
    assert key.Equals(clone)
    assert_equal key, clone
    refute key != clone
    assert_equal 4_194_305, key.GetHashCode
    assert_equal key.GetHashCode, key.hash

    clone.Value = 20
    assert_equal 2.0, key.Value
    refute key.Equals(clone)
    zero = CurveKey.new(0.0, -0.0)
    negative_zero = CurveKey.new(-0.0, 0.0)
    assert_equal zero, negative_zero
    assert_equal zero.GetHashCode, negative_zero.GetHashCode

    nan = CurveKey.new(Float::NAN, 1)
    refute nan.Equals(nan)
    refute nan == nan
    assert nan != nan
    refute key.Equals(Object.new)
    refute key.Equals(nil)
  end

  def test_curve_key_compare_to_uses_xna_direct_single_branches
    low = CurveKey.new(-1, 0)
    equal = CurveKey.new(-1, 99)
    high = CurveKey.new(1, 0)
    assert_equal(-1, low.CompareTo(high))
    assert_equal 0, low.CompareTo(equal)
    assert_equal 1, high.CompareTo(low)
    assert_equal 0, CurveKey.new(0.0, 0).CompareTo(CurveKey.new(-0.0, 1))
    assert_equal(-1, CurveKey.new(-Float::INFINITY, 0).CompareTo(low))
    assert_equal 1, CurveKey.new(Float::INFINITY, 0).CompareTo(high)

    nan_a = CurveKey.new(Float::NAN, 0)
    nan_b = CurveKey.new(Float::NAN, 0)
    assert_equal 1, nan_a.CompareTo(low)
    assert_equal 1, low.CompareTo(nan_a)
    assert_equal 1, nan_a.CompareTo(nan_b)
    assert_raises(TypeError) { low.CompareTo(nil) }
  end

  def test_collection_sorted_insertion_duplicate_stability_and_live_references
    keys = CurveKeyCollection.new
    first = CurveKey.new(0, 0)
    middle_a = CurveKey.new(1, 10)
    middle_b = CurveKey.new(1, 20)
    last = CurveKey.new(2, 30)
    keys.Add(last)
    keys.Add(middle_a)
    keys.Add(first)
    keys.Add(middle_b)
    keys.Add(middle_a)
    assert_equal [0, 1, 1, 1, 2], (0...keys.Count).map { |index| keys[index].Position }
    assert_same middle_a, keys[1]
    assert_same middle_b, keys[2]
    assert_same middle_a, keys[3]
    middle_a.Value = 11
    assert_equal [11, 20, 11], [keys[1].Value, keys[2].Value, keys[3].Value]

    nan_a = CurveKey.new(Float::NAN, 1)
    nan_b = CurveKey.new(Float::NAN, 2)
    keys.Add(nan_a)
    keys.Add(nan_b)
    assert_same nan_b, keys[0]
    assert_same nan_a, keys[1]
    assert_raises(TypeError) { keys.Add(nil) }
    assert_raises(TypeError) { keys.Add(Object.new) }
  end

  def test_collection_lookup_remove_and_nan_follow_curve_key_value_equality
    keys = CurveKeyCollection.new
    first = CurveKey.new(0, 1)
    equal = first.Clone
    last = CurveKey.new(2, 3)
    keys.Add(first)
    keys.Add(equal)
    keys.Add(last)
    assert_equal 0, keys.IndexOf(equal)
    assert keys.Contains(CurveKey.new(0, 1))
    assert keys.Remove(equal)
    assert_same equal, keys[0]
    refute keys.Remove(CurveKey.new(9, 9))
    assert_equal(-1, keys.IndexOf(nil))
    refute keys.Contains(nil)
    refute keys.Remove(nil)

    nan = CurveKey.new(Float::NAN, 1)
    keys.Add(nan)
    assert_equal(-1, keys.IndexOf(nan))
    refute keys.Contains(nan)

    keys.RemoveAt(1)
    assert_equal 2, keys.Count
    assert_raises(IndexError) { keys.RemoveAt(-1) }
    assert_raises(IndexError) { keys.RemoveAt(keys.Count) }
    keys.Clear
    keys.Clear
    assert_equal 0, keys.Count
    refute keys.IsReadOnly
  end

  def test_collection_item_replacement_repositions_and_rejects_negative_indices
    keys = CurveKeyCollection.new
    [0, 1, 2].each { |position| keys.Add(CurveKey.new(position, position * 10)) }
    same_position = CurveKey.new(1, 99)
    keys[1] = same_position
    assert_same same_position, keys[1]

    moved = CurveKey.new(3, 30)
    keys[0] = moved
    assert_equal [1, 2, 3], (0...keys.Count).map { |index| keys[index].Position }
    assert_same moved, keys[2]

    duplicate = CurveKey.new(2, 200)
    keys[0] = duplicate
    assert_equal [2, 2, 3], (0...keys.Count).map { |index| keys[index].Position }
    assert_same duplicate, keys[1]
    assert_raises(TypeError) { keys[-1] = nil }
    assert_raises(IndexError) { keys[-1] = CurveKey.new(0, 0) }
    assert_raises(IndexError) { keys[keys.Count] }
    assert_raises(IndexError) { keys.RemoveAt(-1) }
  end

  def test_collection_copy_to_validation_order_capacity_and_reference_identity
    keys = CurveKeyCollection.new
    first = CurveKey.new(0, 1)
    second = CurveKey.new(1, 2)
    keys.Add(first)
    keys.Add(second)
    destination = [nil, nil, nil, nil]
    assert_nil keys.CopyTo(destination, 1)
    assert_same first, destination[1]
    assert_same second, destination[2]
    assert_nil destination[0]
    assert_nil destination[3]
    exact = [nil, nil]
    keys.CopyTo(exact, 0)
    assert_equal [first, second], exact

    assert_raises(TypeError) { keys.CopyTo(nil, 0) }
    assert_raises(IndexError) { keys.CopyTo([], -1) }
    assert_raises(ArgumentError) { keys.CopyTo([nil], 0) }
    assert_raises(ArgumentError) { keys.CopyTo([nil, nil], 1) }
    empty = CurveKeyCollection.new
    assert_nil empty.CopyTo([], 0)
    assert_raises(ArgumentError) { empty.CopyTo([], 1) }
  end

  def test_collection_clone_is_new_and_shallow
    keys = CurveKeyCollection.new
    key = CurveKey.new(1, 10)
    keys.Add(key)
    clone = keys.Clone
    refute_same keys, clone
    assert_same key, clone[0]
    clone[0].Value = 42
    assert_equal 42.0, keys[0].Value
    clone.Add(CurveKey.new(2, 20))
    assert_equal 1, keys.Count
    assert_equal 2, clone.Count
  end

  def test_collection_enumerators_are_fresh_independent_and_fail_fast
    keys = CurveKeyCollection.new
    first = CurveKey.new(0, 0)
    second = CurveKey.new(1, 1)
    keys.Add(first)
    keys.Add(second)
    left = keys.GetEnumerator
    right = keys.GetEnumerator
    refute_same left, right
    assert_same first, left.next
    assert_same first, right.next
    assert_same second, left.next
    assert_same second, right.next
    assert_raises(StopIteration) { left.next }

    invalidated = keys.GetEnumerator
    assert_same first, invalidated.next
    keys.Add(CurveKey.new(2, 2))
    assert_raises(RuntimeError) { invalidated.next }

    copy_safe = keys.GetEnumerator
    destination = Array.new(keys.Count)
    keys.CopyTo(destination, 0)
    assert_same first, copy_safe.next
    refute keys.Remove(CurveKey.new(9, 9))
    assert_same second, copy_safe.next

    replaced = keys.GetEnumerator
    keys[0] = CurveKey.new(0, 99)
    assert_raises(RuntimeError) { replaced.next }
  end

  def test_curve_defaults_keys_identity_and_is_constant_definition
    curve = Curve.new
    assert_same F::CurveLoopType::Constant, curve.PreLoop
    assert_same F::CurveLoopType::Constant, curve.PostLoop
    assert_same curve.Keys, curve.Keys
    assert curve.IsConstant
    assert_equal 0.0, curve.Evaluate(-Float::INFINITY)
    assert_equal 0.0, curve.Evaluate(Float::NAN)
    curve.Keys.Add(CurveKey.new(5, 7))
    assert curve.IsConstant
    [-Float::INFINITY, 5, Float::INFINITY, Float::NAN].each { |position| assert_equal 7.0, curve.Evaluate(position) }
    curve.Keys.Add(CurveKey.new(6, 7))
    refute curve.IsConstant
    assert_raises(RangeError) { curve.PreLoop = 8 }
    assert_raises(TypeError) { curve.PostLoop = Object.new }
  end

  def test_curve_clone_has_independent_collection_shared_keys_and_copied_modes
    curve = two_key_curve
    curve.PreLoop = F::CurveLoopType::Cycle
    curve.PostLoop = F::CurveLoopType::Oscillate
    clone = curve.Clone
    refute_same curve, clone
    refute_same curve.Keys, clone.Keys
    assert_same curve.Keys[0], clone.Keys[0]
    assert_same curve.PreLoop, clone.PreLoop
    assert_same curve.PostLoop, clone.PostLoop
    clone.Keys[0].Value = 42
    assert_equal 42.0, curve.Keys[0].Value
    clone.Keys.RemoveAt(1)
    assert_equal 2, curve.Keys.Count
    assert_equal 1, clone.Keys.Count

    dirty = two_key_curve
    dirty.PreLoop = F::CurveLoopType::Cycle
    dirty_clone = dirty.Clone
    assert_equal 5.0, dirty.Evaluate(4.0)
    assert_equal 10.0, dirty_clone.Evaluate(4.0), "XNA Clone marks copied cache values valid"
  end

  def test_evaluate_segments_hermite_step_duplicates_and_nonfinite_positions
    ordinary = Curve.new
    ordinary.Keys.Add(CurveKey.new(0, 0))
    ordinary.Keys.Add(CurveKey.new(1, 10))
    assert_equal 0x3fc8_0000, bits(ordinary.Evaluate(0.25))
    assert_equal [0.0, 10.0], [ordinary.Evaluate(0), ordinary.Evaluate(1)]

    asymmetric = Curve.new
    asymmetric.Keys.Add(CurveKey.new(0, 0, 99, 4))
    asymmetric.Keys.Add(CurveKey.new(2, 10, -2, 77))
    assert_equal 0x40b8_0000, bits(asymmetric.Evaluate(1))

    step = Curve.new
    step.Keys.Add(CurveKey.new(0, 2, 0, 0, F::CurveContinuity::Step))
    step.Keys.Add(CurveKey.new(1, 9))
    assert_equal 2.0, step.Evaluate(0.999)
    assert_equal 9.0, step.Evaluate(1.0)

    duplicates = Curve.new
    duplicates.Keys.Add(CurveKey.new(1, 10))
    duplicates.Keys.Add(CurveKey.new(1, 20))
    duplicates.Keys.Add(CurveKey.new(2, 30))
    assert_equal 10.0, duplicates.Evaluate(1.0)
    assert_equal 20.0, duplicates.Evaluate([0x3f80_0001].pack("L<").unpack1("e"))

    nan_step = Curve.new
    nan_step.Keys.Add(CurveKey.new(0, 10, 0, 0, F::CurveContinuity::Step))
    nan_step.Keys.Add(CurveKey.new(1, 20, 0, 0, F::CurveContinuity::Step))
    assert_equal 20.0, nan_step.Evaluate(Float::NAN)
    assert_equal 20.0, nan_step.Evaluate(Float::INFINITY)
    assert ordinary.Evaluate(Float::NAN).nan?
    assert_equal 10.0, ordinary.Evaluate(Float::INFINITY)
    ordinary.PostLoop = F::CurveLoopType::Cycle
    assert ordinary.Evaluate(Float::INFINITY).nan?
  end

  def test_all_pre_and_post_loop_modes_and_linear_units
    pre_expected = {
      F::CurveLoopType::Constant => 0.0,
      F::CurveLoopType::Cycle => 5.0,
      F::CurveLoopType::CycleOffset => -5.0,
      F::CurveLoopType::Oscillate => 5.0
    }
    post_expected = {
      F::CurveLoopType::Constant => 10.0,
      F::CurveLoopType::Cycle => 5.0,
      F::CurveLoopType::CycleOffset => 15.0,
      F::CurveLoopType::Oscillate => 5.0
    }
    pre_expected.each do |mode, expected|
      curve = two_key_curve
      curve.PreLoop = mode
      assert_equal expected, curve.Evaluate(4.0), mode.name
    end
    post_expected.each do |mode, expected|
      curve = two_key_curve
      curve.PostLoop = mode
      assert_equal expected, curve.Evaluate(8.0), mode.name
    end

    linear = two_key_curve
    linear.Keys[0].TangentIn = 2
    linear.Keys[1].TangentOut = 3
    linear.PreLoop = F::CurveLoopType::Linear
    linear.PostLoop = F::CurveLoopType::Linear
    assert_equal(-2.0, linear.Evaluate(4.0))
    assert_equal 13.0, linear.Evaluate(8.0)
  end

  def test_negative_exact_cycles_cycle_offsets_and_oscillation_parity
    cycle = two_key_curve
    offset = two_key_curve
    oscillate = two_key_curve
    cycle.PreLoop = F::CurveLoopType::Cycle
    offset.PreLoop = F::CurveLoopType::CycleOffset
    oscillate.PreLoop = F::CurveLoopType::Oscillate
    assert_equal 10.0, cycle.Evaluate(3.0)
    assert_equal(-10.0, offset.Evaluate(3.0))
    assert_equal 10.0, oscillate.Evaluate(3.0)
    assert_in_delta 5.0, cycle.Evaluate(2.0), 1.0e-6
    assert_in_delta(-15.0, offset.Evaluate(2.0), 1.0e-6)
    assert_in_delta 5.0, oscillate.Evaluate(2.0), 1.0e-6

    post = two_key_curve
    post.PostLoop = F::CurveLoopType::CycleOffset
    assert_equal 20.0, post.Evaluate(9.0)

    descending = Curve.new
    descending.Keys.Add(CurveKey.new(0, 10))
    descending.Keys.Add(CurveKey.new(1, 0))
    descending.PostLoop = F::CurveLoopType::CycleOffset
    assert_equal(-5.0, descending.Evaluate(1.5))
  end

  def test_flat_linear_smooth_and_mixed_tangents_with_nonuniform_spacing
    curve = Curve.new
    curve.Keys.Add(CurveKey.new(0, 0))
    curve.Keys.Add(CurveKey.new(2, 10))
    curve.Keys.Add(CurveKey.new(5, 40))
    curve.ComputeTangent(1, F::CurveTangent::Flat)
    assert_equal [0.0, 0.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]
    curve.ComputeTangent(1, F::CurveTangent::Linear)
    assert_equal [10.0, 30.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]
    curve.ComputeTangent(1, F::CurveTangent::Smooth)
    assert_equal [16.0, 24.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]
    curve.ComputeTangent(1, F::CurveTangent::Flat, F::CurveTangent::Linear)
    assert_equal [0.0, 30.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]
    curve.ComputeTangent(1, F::CurveTangent::Linear, F::CurveTangent::Smooth)
    assert_equal [10.0, 24.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]

    curve.ComputeTangents(F::CurveTangent::Smooth)
    assert_equal [0.0, 10.0], [curve.Keys[0].TangentIn, curve.Keys[0].TangentOut]
    assert_equal [16.0, 24.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]
    assert_equal [30.0, 0.0], [curve.Keys[2].TangentIn, curve.Keys[2].TangentOut]
    curve.Keys[0].TangentIn = 999
    curve.Keys[1].TangentOut = -999
    curve.ComputeTangents(F::CurveTangent::Smooth)
    assert_equal [16.0, 24.0], [curve.Keys[1].TangentIn, curve.Keys[1].TangentOut]
  end

  def test_tangent_epsilon_duplicate_positions_singleton_and_invalid_indices
    epsilon = Curve.new
    epsilon.Keys.Add(CurveKey.new(0, 0))
    epsilon.Keys.Add(CurveKey.new(1, 5.0e-9))
    epsilon.Keys.Add(CurveKey.new(2, 1.0e-8))
    epsilon.ComputeTangent(1, F::CurveTangent::Smooth)
    assert_equal [0, 0], [epsilon.Keys[1].TangentIn, epsilon.Keys[1].TangentOut].map { |value| bits(value) }

    singleton = Curve.new
    singleton.Keys.Add(CurveKey.new(1, 9, 2, 3))
    singleton.ComputeTangents(F::CurveTangent::Smooth)
    assert_equal [0.0, 0.0], [singleton.Keys[0].TangentIn, singleton.Keys[0].TangentOut]

    duplicate = Curve.new
    duplicate.Keys.Add(CurveKey.new(1, 0))
    duplicate.Keys.Add(CurveKey.new(1, 1))
    duplicate.Keys.Add(CurveKey.new(1, 2))
    duplicate.ComputeTangent(1, F::CurveTangent::Smooth)
    assert duplicate.Keys[1].TangentIn.nan?
    assert duplicate.Keys[1].TangentOut.nan?

    assert_raises(IndexError) { epsilon.ComputeTangent(-1, F::CurveTangent::Flat) }
    assert_raises(IndexError) { epsilon.ComputeTangent(epsilon.Keys.Count, F::CurveTangent::Flat) }
    assert_raises(ArgumentError) { epsilon.ComputeTangents }
  end
end
