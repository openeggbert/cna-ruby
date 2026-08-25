# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 23 — TouchLocation and GestureSample, derived from the pinned
# Microsoft.Xna.Framework.Input.Touch.dll IL (SHA-256 b0585224…).
#
# Both are publicly constructible XNA value types with no native reachability, so they are managed
# value contracts this binding can carry faithfully. Nothing here reads a touch device: TouchPanel,
# TouchCollection and all gesture recognition remain absent, and no path in this binding produces
# either type.
class TouchValueTypesTest < Minitest::Test
  F = Microsoft::Xna::Framework
  T = F::Input::Touch
  TL = T::TouchLocation
  S = T::TouchLocationState

  ROOT = Pathname(__dir__).join("..").expand_path
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read).freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze

  def location(id: 3, state: S::Moved, x: 1.5, y: -2.25)
    TL.new(id, state, F::Vector2.new(x, y))
  end

  def chained(id: 3, state: S::Moved, x: 1.5, y: -2.25, prev_state: S::Pressed, px: 0.5, py: 0.25)
    TL.new(id, state, F::Vector2.new(x, y), prev_state, F::Vector2.new(px, py))
  end

  # ----------------------------------------------------------------------------- IL provenance

  def test_both_types_come_from_the_pinned_touch_assembly_and_are_pure_managed
    %w[Microsoft.Xna.Framework.Input.Touch.TouchLocation
       Microsoft.Xna.Framework.Input.Touch.GestureSample].each do |name|
      entry = IL.fetch("types").fetch(name)
      assert_equal "Microsoft.Xna.Framework.Input.Touch.dll", entry.fetch("assembly"), name
      assert_equal "b0585224c18022c3661057ae79544644c10f33f1dc529678364f3d6b25151c25",
                   entry.fetch("assemblySha256"), name
      refute entry.fetch("nativeReachable"), name
      refute entry.fetch("declaresNativeEntryPoint"), name
      assert_includes STRICT.fetch("completeTypeNames"), name, name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
    end
    # Seven private fields, three constructors, six declared non-constructor methods before the
    # three property getters are counted; the internal seven-argument constructor is not public.
    assert_equal 7, IL.fetch("types").fetch("Microsoft.Xna.Framework.Input.Touch.TouchLocation").fetch("declaredFields")
    assert_equal 6, IL.fetch("types").fetch("Microsoft.Xna.Framework.Input.Touch.GestureSample").fetch("declaredFields")
  end

  # ------------------------------------------------------------------------------ TouchLocation

  def test_the_three_argument_constructor_leaves_the_previous_location_empty
    value = location
    assert_equal 3, value.Id
    assert_equal S::Moved, value.State
    assert_equal F::Vector2.new(1.5, -2.25), value.Position
    # prevState is the literal 0, which is Invalid, and prevX/prevY are 0.
    found, previous = value.TryGetPreviousLocation
    assert_equal false, found
    assert_equal(-1, previous.Id)
    assert_equal S::Invalid, previous.State
    assert_equal F::Vector2.new(0.0, 0.0), previous.Position
  end

  def test_the_five_argument_constructor_stores_the_previous_location
    found, previous = chained.TryGetPreviousLocation
    assert_equal true, found
    # The previous location keeps this location's id, takes the previous state and position, and
    # has no previous location of its own.
    assert_equal 3, previous.Id
    assert_equal S::Pressed, previous.State
    assert_equal F::Vector2.new(0.5, 0.25), previous.Position
    assert_equal false, previous.TryGetPreviousLocation.first
  end

  def test_try_get_previous_location_answers_both_halves_of_the_clr_result
    # The CLR fills the out value on both branches, so neither half is dropped.
    [location, chained].each do |value|
      result = value.TryGetPreviousLocation
      assert_instance_of Array, result
      assert_equal 2, result.length
      assert_includes [true, false], result.first
      assert_instance_of TL, result.last
    end
  end

  def test_previous_state_invalid_is_the_only_thing_that_makes_it_empty
    assert_equal false, chained(prev_state: S::Invalid).TryGetPreviousLocation.first
    [S::Released, S::Pressed, S::Moved].each do |state|
      assert_equal true, chained(prev_state: state).TryGetPreviousLocation.first, state.to_s
    end
  end

  def test_position_answers_a_fresh_vector_every_read
    value = location
    refute_same value.Position, value.Position
    assert_equal value.Position, value.Position
  end

  def test_equals_and_the_equality_operator_deliberately_disagree
    # Equals compares id, x, y, prevX and prevY. op_Equality compares all seven fields, including
    # both states. XNA really does this, and it is preserved rather than normalised.
    left = location(state: S::Moved)
    right = location(state: S::Released)
    assert left.Equals(right), "Equals ignores state"
    refute left == right, "op_Equality compares state"

    both = chained(prev_state: S::Pressed)
    other = chained(prev_state: S::Released)
    assert both.Equals(other), "Equals ignores prevState"
    refute both == other, "op_Equality compares prevState"

    # Everything the two do agree on.
    refute left.Equals(location(id: 4))
    refute left.Equals(location(x: 9.0))
    refute left.Equals(location(y: 9.0))
    refute left.Equals(chained)
    refute left.Equals(:not_a_touch_location)
    assert_equal left, left.dup
  end

  def test_inequality_is_the_negation_of_equality
    left = location
    assert left != location(id: 4)
    refute left != left.dup
    assert_equal(left == left.dup, !(left != left.dup))
  end

  def test_nan_is_never_equal_to_itself_in_either_comparison
    # Every IL comparison is bne.un, so an unordered operand is never equal.
    nan = TL.new(1, S::Pressed, F::Vector2.new(Float::NAN, 0.0))
    refute nan == nan.dup
    refute nan.Equals(nan.dup)
    # A NaN previous coordinate defeats Equals too, since it compares prevX and prevY.
    chained_nan = TL.new(1, S::Pressed, F::Vector2.new(0.0, 0.0), S::Moved, F::Vector2.new(Float::NAN, 0.0))
    refute chained_nan.Equals(chained_nan.dup)
  end

  def test_get_hash_code_sums_only_id_x_and_y
    numeric = CNA::Runtime::Numeric
    value = chained
    assert_equal numeric.hash32_sum(3, numeric.single_hash(1.5), numeric.single_hash(-2.25)),
                 value.GetHashCode
    # The previous location and both states are outside the hash.
    assert_equal location.GetHashCode, chained.GetHashCode
    assert_equal location(state: S::Released).GetHashCode, location(state: S::Moved).GetHashCode
    refute_equal location.GetHashCode, location(id: 4).GetHashCode
    # Equal values hash equally, which is what a Ruby Hash needs.
    assert_equal value.GetHashCode, value.dup.GetHashCode
    assert_equal value.hash, value.dup.hash
    assert_equal 1, {value => :a, value.dup => :b}.size
  end

  def test_to_string_is_the_position_only_format
    assert_equal "{Position:{X:1.5 Y:-2.25}}", location.ToString
    assert_equal location.ToString, location.to_s
    # The previous location never appears.
    assert_equal location.ToString, chained.ToString
  end

  def test_constructor_arity_and_boundary_validation
    assert_raises(ArgumentError) { TL.new(1, S::Moved) }
    assert_raises(ArgumentError) { TL.new(1, S::Moved, F::Vector2.new(0, 0), S::Moved) }
    assert_raises(TypeError) { TL.new(1, S::Moved, :not_a_vector) }
    # The enum policy rejects an undeclared integer, and a foreign type outright.
    assert_raises(RangeError) { TL.new(1, 99, F::Vector2.new(0, 0)) }
    assert_raises(TypeError) { TL.new(1, T::GestureType::Tap, F::Vector2.new(0, 0)) }
    assert_raises(RangeError) { TL.new(2**31, S::Moved, F::Vector2.new(0, 0)) }
    # XNA itself validates nothing, so every in-range value is accepted.
    assert_equal(-2_147_483_648, TL.new(-2**31, S::Invalid, F::Vector2.new(0, 0)).Id)
  end

  def test_value_copy_semantics
    value = chained
    copy = value.dup
    refute_same value, copy
    assert_equal value, copy
    assert_equal value.TryGetPreviousLocation.last.Position, copy.TryGetPreviousLocation.last.Position
    assert copy.clone.frozen? == copy.frozen?
  end

  # ------------------------------------------------------------------------------ GestureSample

  def sample(type: T::GestureType::Tap, timestamp: 1.25)
    T::GestureSample.new(type, timestamp, F::Vector2.new(1, 2), F::Vector2.new(3, 4),
                         F::Vector2.new(5, 6), F::Vector2.new(7, 8))
  end

  def test_gesture_sample_is_pure_storage
    value = sample
    assert_equal T::GestureType::Tap, value.GestureType
    assert_equal 1.25, value.Timestamp
    assert_equal F::Vector2.new(1, 2), value.Position
    assert_equal F::Vector2.new(3, 4), value.Position2
    assert_equal F::Vector2.new(5, 6), value.Delta
    assert_equal F::Vector2.new(7, 8), value.Delta2
    assert_equal %i[Delta Delta2 GestureType Position Position2 Timestamp clone dup],
                 T::GestureSample.public_instance_methods(false).sort
  end

  def test_gesture_sample_reads_and_stores_copies
    shared = F::Vector2.new(1, 2)
    value = T::GestureSample.new(T::GestureType::Tap, 0.0, shared, shared, shared, shared)
    refute_same value.Position, value.Position
    refute_same value.Position, value.Position2
    assert_equal value.Position, value.Position2
  end

  def test_gesture_sample_accepts_combined_flags_and_validates_its_arguments
    combined = T::GestureType::Tap | T::GestureType::Hold
    assert_equal combined, sample(type: combined).GestureType
    assert_raises(TypeError) { sample(timestamp: "1.25") }
    assert_raises(TypeError) { T::GestureSample.new(T::GestureType::Tap, 0.0, 1, 2, 3, 4) }
    assert_raises(ArgumentError) { T::GestureSample.new(T::GestureType::Tap, 0.0) }
    assert_equal 2.0, sample(timestamp: 2).Timestamp
    assert_instance_of Float, sample(timestamp: 2).Timestamp
  end

  def test_gesture_sample_projects_no_undeclared_contract
    # The struct declares no Equals, GetHashCode, ToString or operator, so none is invented.
    value = sample
    refute_equal value, sample
    refute T::GestureSample.method_defined?(:GetHashCode)
    refute T::GestureSample.method_defined?(:ToString)
    refute T::GestureSample.method_defined?(:Equals)
    assert_equal value.Position, value.dup.Position
    refute_same value, value.dup
  end

  # ------------------------------------------------------------------------ nothing reads a device

  # Foundations 31 and 32 completed the whole Input.Touch namespace from IL. Not one member of it
  # reads a device: TouchPanel.GetCapabilities answers the CLR default struct value, GetState an
  # empty collection, and no touch route was bound.
  def test_no_touch_device_surface_exists
    %i[TouchPanelState].each { |name| refute T.const_defined?(name, false), name.to_s }
    assert T.const_defined?(:TouchCollection, false)
    assert T::TouchCollection.const_defined?(:Enumerator, false)
    refute T::TouchPanel.GetCapabilities.IsConnected
    assert_equal 0, T::TouchPanel.GetCapabilities.MaximumTouchCount
    assert_equal 0, T::TouchPanel.GetState.Count
    %i[GetCapabilities ReadGesture IsGestureAvailable GetState EnabledGestures]
      .each { |name| refute TL.respond_to?(name), name.to_s }
    %i[GetCapabilities ReadGesture IsGestureAvailable GetState EnabledGestures]
      .each { |name| refute T::TouchCollection.respond_to?(name), name.to_s }
    assert_equal 39, CNA::Native::Manifest::FUNCTIONS.length
    assert_equal 59, CNA::Native::Manifest::CONSTANTS.length
  end
end
