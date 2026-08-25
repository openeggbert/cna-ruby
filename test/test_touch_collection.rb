# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 31 — `TouchCollection` and its nested `TouchCollection+Enumerator`, closed together.
#
# Neither could ever have been closed alone. The declaring type's `GetEnumerator` returns the nested
# one, and the nested one's `Current` and `MoveNext` call the declaring type's `Item` and `Count`, so
# the dependency runs both ways. Native frontier 2 taught the analyzer to treat a nested type's
# declaring type as a dependency, which is what made the pair classify honestly instead of looking
# like one consumable type and one blocked one.
#
# Everything asserted here is read out of the pinned Microsoft.Xna.Framework.Input.Touch.dll IL
# (SHA-256 b0585224…). The struct declares eight `TouchLocation` slots and an `int32` count, never a
# list, which is the whole eight-location ceiling.
class TouchCollectionTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  F = Microsoft::Xna::Framework
  T = Microsoft::Xna::Framework::Input::Touch
  C = T::TouchCollection
  S = T::TouchLocationState

  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)

  def location(id, state = S::Pressed, x = 1.0, y = 2.0)
    T::TouchLocation.new(id, state, F::Vector2.new(x, y))
  end

  def previous_location(id)
    T::TouchLocation.new(id, S::Moved, F::Vector2.new(3.0, 4.0), S::Pressed, F::Vector2.new(1.0, 1.0))
  end

  def collection(*touches) = C.new(touches)

  # --------------------------------------------------------------------------- both are complete

  def test_the_pair_is_complete_and_each_reports_zero_local_diagnostics
    %w[Microsoft.Xna.Framework.Input.Touch.TouchCollection
       Microsoft.Xna.Framework.Input.Touch.TouchCollection+Enumerator].each do |name|
      assert_includes STRICT.fetch("completeTypeNames"), name
      assert_equal 0, STRICT.fetch("localDiagnostics").fetch(name), name
    end
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
    assert_equal 0, STRICT.fetch("PARAMETER_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("RETURN_MAPPING_MISMATCH")
  end

  # The nested type keeps the naming policy the reference contract uses: `Parent+Child` in CLR
  # spelling, `Parent::Child` in Ruby.
  def test_the_nested_enumerator_keeps_the_nested_naming_policy
    assert_equal "Microsoft::Xna::Framework::Input::Touch::TouchCollection::Enumerator",
                 C::Enumerator.name
    assert_same C::Enumerator, C.const_get(:Enumerator, false)
    refute T.const_defined?(:Enumerator, false), "the nested type must not leak into its namespace"
    refute T.const_defined?(:TouchCollectionEnumerator, false)
  end

  # ---------------------------------------------------------------------------- the constructor

  def test_the_constructor_validates_exactly_what_the_il_validates
    error = assert_raises(ArgumentError) { C.new(nil) }
    assert_equal "touches", error.message, "the CLR names the parameter in the ldstr operand"

    assert_raises(TypeError) { C.new("not an array") }
    assert_raises(TypeError) { C.new([Object.new]) }

    # `ldlen; ldc.i4.8; ble.s` — eight is accepted and nine is not.
    assert_equal 8, C.new(Array.new(8) { |index| location(index) }).Count
    range = assert_raises(RangeError) { C.new(Array.new(9) { |index| location(index) }) }
    assert_equal "touches", range.message

    # An empty collection is legal and still reports itself connected.
    empty = C.new([])
    assert_equal 0, empty.Count
    assert empty.IsConnected
  end

  def test_the_constructor_sets_is_connected_to_the_literal_true
    assert collection.IsConnected
    assert collection(location(1)).IsConnected
    refute C.public_method_defined?(:IsConnected=)
  end

  # Each element is expanded through TouchLocation.TryGetPreviousLocation: with a previous location
  # the entry carries that location's state and position, without one it carries the literal 0,
  # which is TouchLocationState.Invalid, and a zero previous position.
  def test_each_element_is_expanded_through_try_get_previous_location
    plain = location(3)
    refute plain.TryGetPreviousLocation.first
    carried = previous_location(4)
    assert carried.TryGetPreviousLocation.first

    touches = collection(plain, carried)
    assert_equal 2, touches.Count
    assert_equal 3, touches[0].Id
    assert_equal S::Pressed, touches[0].State
    refute touches[0].TryGetPreviousLocation.first, "no previous location survives as Invalid"

    assert_equal 4, touches[1].Id
    assert_equal S::Moved, touches[1].State
    found, previous = touches[1].TryGetPreviousLocation
    assert found
    assert_equal S::Pressed, previous.State
    assert_equal F::Vector2.new(1.0, 1.0), previous.Position
  end

  # -------------------------------------------------------------------------------- the reads

  def test_count_is_the_location_count_field
    assert_equal 0, collection.Count
    assert_equal 1, collection(location(1)).Count
    assert_equal 3, collection(location(1), location(2), location(3)).Count
  end

  # `get_IsReadOnly` is `ldc.i4.1; ret` — a literal, with no backing field.
  def test_is_read_only_is_the_literal_true
    assert collection.IsReadOnly
    assert collection(location(1)).IsReadOnly
    assert C.new(Array.new(8) { |index| location(index) }).IsReadOnly
  end

  # The indexer constructs ArgumentOutOfRangeException("index") in its own IL, which the
  # thrown-exception register maps to RangeError. This is not the forwarding-indexer case that
  # raises IndexError.
  def test_the_indexer_bounds_and_its_measured_exception
    touches = collection(location(1), location(2))
    assert_equal 1, touches[0].Id
    assert_equal 2, touches[1].Id

    [-1, 2, 3, 8, 99].each do |index|
      error = assert_raises(RangeError) { touches[index] }
      assert_equal "index", error.message, index.to_s
    end
    assert_raises(RangeError) { collection[0] }
    assert_raises(TypeError) { touches[nil] }
    assert_raises(TypeError) { touches["0"] }
  end

  # The struct is returned by value, so each read answers a fresh object.
  def test_the_indexer_answers_a_fresh_copy
    touches = collection(location(1))
    refute_same touches[0], touches[0]
    assert_equal touches[0], touches[0]
  end

  # `IndexOf` scans 0...Count with TouchLocation::op_Equality, which compares all seven fields —
  # not the narrower Equals, which ignores both states.
  def test_index_of_scans_with_op_equality_and_answers_minus_one_when_absent
    first = location(1)
    second = location(2)
    touches = collection(first, second)
    assert_equal 0, touches.IndexOf(touches[0])
    assert_equal 1, touches.IndexOf(touches[1])
    assert_equal(-1, touches.IndexOf(location(99)))
    assert_equal(-1, collection.IndexOf(location(1)))

    # Same fields but a different state: op_Equality says no, and Equals would say yes.
    differing = T::TouchLocation.new(1, S::Moved, F::Vector2.new(1.0, 2.0))
    assert differing.Equals(touches[0]), "Equals ignores State, which is the measured divergence"
    refute_equal differing, touches[0]
    assert_equal(-1, touches.IndexOf(differing))

    assert_raises(TypeError) { touches.IndexOf(nil) }
    assert_raises(TypeError) { touches.IndexOf(Object.new) }
  end

  # `Contains` is literally `IndexOf(item) < 0` negated, never a separate comparison.
  def test_contains_is_index_of_negated
    touches = collection(location(1), location(2))
    assert touches.Contains(touches[0])
    assert touches.Contains(touches[1])
    refute touches.Contains(location(99))
    refute collection.Contains(location(1))
    assert_equal touches.IndexOf(touches[1]) >= 0, touches.Contains(touches[1])
  end

  def test_find_by_id_answers_the_ordered_pair_and_fills_both_branches
    touches = collection(location(5), location(9))
    found, located = touches.FindById(9)
    assert found
    assert_equal 9, located.Id

    # The CLR fills the out value with `initobj` on the false branch, so the default TouchLocation
    # is returned rather than nothing: neither half of the result is dropped.
    missing, default = touches.FindById(1234)
    refute missing
    assert_equal 0, default.Id
    assert_equal S::Invalid, default.State
    assert_equal F::Vector2.new(0.0, 0.0), default.Position
    refute default.TryGetPreviousLocation.first

    assert_equal [false, default], collection.FindById(0).then { |result| [result[0], result[1]] }
    assert_raises(TypeError) { touches.FindById(nil) }
  end

  def test_copy_to_writes_from_the_offset_and_validates_what_the_il_validates
    touches = collection(location(1), location(2))
    destination = Array.new(4)
    assert_nil touches.CopyTo(destination, 1)
    assert_nil destination[0]
    assert_equal [1, 2], destination[1..2].map(&:Id)
    assert_nil destination[3]

    null = assert_raises(ArgumentError) { touches.CopyTo(nil, 0) }
    assert_equal "array", null.message
    assert_raises(TypeError) { touches.CopyTo("no", 0) }
    assert_raises(TypeError) { touches.CopyTo(destination, nil) }

    # Both remaining checks throw ArgumentOutOfRangeException("arrayIndex"), which maps to
    # RangeError, and the second is `array.Length >= arrayIndex + Count`.
    negative = assert_raises(RangeError) { touches.CopyTo(destination, -1) }
    assert_equal "arrayIndex", negative.message
    small = assert_raises(RangeError) { touches.CopyTo(Array.new(2), 1) }
    assert_equal "arrayIndex", small.message
    assert_raises(RangeError) { touches.CopyTo(Array.new(1), 0) }

    exact = Array.new(2)
    assert_nil touches.CopyTo(exact, 0)
    assert_equal [1, 2], exact.map(&:Id)
    # An empty collection copies nothing and accepts any non-negative offset that fits.
    assert_nil collection.CopyTo([], 0)
  end

  # ----------------------------------------------------------------------- the refusal to mutate

  # Six members are each a two-instruction body: `newobj NotSupportedException::.ctor(); throw`.
  def test_every_mutating_member_raises_the_projected_not_supported_error
    touches = collection(location(1))
    [-> { touches.Add(location(2)) },
     -> { touches.Clear },
     -> { touches.Insert(0, location(2)) },
     -> { touches.Remove(touches[0]) },
     -> { touches.RemoveAt(0) },
     -> { touches[0] = location(2) }].each do |mutation|
      assert_raises(CNA::Runtime::NotSupportedError, &mutation)
    end
  end

  # The whole reason Foundation 30 refused NotImplementedError: an ordinary rescue must catch this.
  def test_the_refusal_is_catchable_by_an_ordinary_rescue
    touches = collection(location(1))
    caught = begin
      touches.Add(location(2))
    rescue => error
      error
    end
    assert_instance_of CNA::Runtime::NotSupportedError, caught
    refute_operator caught.class, :<=, ::ScriptError
    assert_operator caught.class, :<, ::StandardError
  end

  def test_a_refused_mutation_changes_nothing
    touches = collection(location(1), location(2))
    before = [touches.Count, touches[0].Id, touches[1].Id]
    [-> { touches.Add(location(3)) }, -> { touches.Clear }, -> { touches.RemoveAt(0) }].each do |mutation|
      assert_raises(CNA::Runtime::NotSupportedError, &mutation)
    end
    assert_equal before, [touches.Count, touches[0].Id, touches[1].Id]
  end

  # ------------------------------------------------------------------------------- enumeration

  # `GetEnumerator` copies the collection struct (`ldobj`) into the enumerator, so the enumerator
  # walks a snapshot rather than holding a reference back.
  def test_get_enumerator_answers_a_fresh_enumerator_over_a_copy
    touches = collection(location(1), location(2))
    first = touches.GetEnumerator
    second = touches.GetEnumerator
    assert_instance_of C::Enumerator, first
    refute_same first, second

    assert first.MoveNext
    assert_equal 1, first.Current.Id
    # Advancing one enumerator does not advance the other.
    assert second.MoveNext
    assert_equal 1, second.Current.Id
  end

  def test_the_enumerator_cannot_be_constructed_publicly
    refute C::Enumerator.respond_to?(:new)
    assert_raises(NoMethodError) { C::Enumerator.new(collection) }
    assert_equal 0, REFERENCE.fetch("types")
                             .find { |type| type.fetch("name").end_with?("TouchCollection+Enumerator") }
                             .fetch("members").count { |member| member.fetch("kind") == "constructor" }
  end

  # `position` starts at -1 and `get_Current` forwards to the indexer with no guard of its own, so
  # reading it before the first MoveNext raises exactly what the indexer raises.
  def test_current_before_the_first_move_next_raises_what_the_indexer_raises
    enumerator = collection(location(1)).GetEnumerator
    error = assert_raises(RangeError) { enumerator.Current }
    assert_equal "index", error.message
  end

  def test_move_next_walks_every_element_then_answers_false
    enumerator = collection(location(1), location(2), location(3)).GetEnumerator
    seen = []
    seen << enumerator.Current.Id while enumerator.MoveNext
    assert_equal [1, 2, 3], seen
    refute enumerator.MoveNext
  end

  # MoveNext clamps `position` to Count, so a further MoveNext cannot walk past the end and Current
  # keeps raising rather than answering a stale or out-of-range element.
  def test_after_exhaustion_the_position_is_clamped_and_current_still_raises
    enumerator = collection(location(1)).GetEnumerator
    assert enumerator.MoveNext
    refute enumerator.MoveNext
    refute enumerator.MoveNext
    refute enumerator.MoveNext
    assert_raises(RangeError) { enumerator.Current }
  end

  def test_an_empty_collection_enumerates_nothing
    enumerator = collection.GetEnumerator
    refute enumerator.MoveNext
    assert_raises(RangeError) { enumerator.Current }
  end

  # The IL body of Dispose is a bare `ret`: the enumerator holds nothing to release, and disposing
  # it neither resets it nor stops it.
  def test_dispose_does_nothing_at_all
    enumerator = collection(location(1), location(2)).GetEnumerator
    assert enumerator.MoveNext
    assert_nil enumerator.Dispose
    assert_equal 1, enumerator.Current.Id
    assert enumerator.MoveNext
    assert_equal 2, enumerator.Current.Id
    assert_nil enumerator.Dispose
  end

  # `IEnumerator.Reset` exists in the IL as a private explicit interface implementation, outside the
  # selected surface, so it is deliberately not projected.
  def test_reset_is_not_projected
    refute C::Enumerator.public_method_defined?(:Reset)
    refute C::Enumerator.private_method_defined?(:Reset)
    assert_equal %i[Current Dispose MoveNext],
                 C::Enumerator.public_instance_methods(false).sort
  end

  # --------------------------------------------------------------------- Ruby language support

  # `each` is language support, not an XNA identity, and it is admitted only because the type also
  # projects GetEnumerator.
  def test_each_is_language_support_carrying_get_enumerator
    touches = collection(location(1), location(2))
    seen = []
    assert_same touches, touches.each { |item| seen << item.Id }
    assert_equal [1, 2], seen
    assert_equal [1, 2], touches.map(&:Id)
    assert_equal 2, touches.count
    assert_instance_of ::Enumerator, touches.each
    assert_equal "GetEnumerator", CNA::Runtime::LanguageSupport.derived_from(:each)
    assert C.public_method_defined?(:GetEnumerator)
  end

  # ------------------------------------------------------------------------------ copy semantics

  def test_dup_and_clone_answer_independent_copies
    touches = collection(location(1), location(2))
    copy = touches.dup
    refute_same touches, copy
    assert_equal touches.Count, copy.Count
    assert_equal touches[0], copy[0]
    refute_same touches[0], copy[0]
    assert_equal touches.IsConnected, copy.IsConnected

    frozen = touches.clone(freeze: false)
    refute frozen.frozen?
    assert_equal touches.Count, frozen.Count
  end

  # --------------------------------------------------------------- nothing produces one of these

  # Foundation 32 added TouchPanel, whose GetState answers an empty collection derived from IL
  # rather than from a device. The collection itself still has no producer of its own.
  def test_nothing_in_this_binding_produces_a_touch_collection_from_a_device
    assert_equal 0, T::TouchPanel.GetState.Count
    refute T::TouchPanel.GetCapabilities.IsConnected
    refute C.respond_to?(:GetState)
    refute C.public_method_defined?(:Update)
    refute C.private_method_defined?(:Update)
    # No native route was bound for touch.
    assert_equal 49, CNA::Native::Manifest::FUNCTIONS.length
    assert(CNA::Native::Manifest::FUNCTIONS.none? { |name, _| name.to_s.include?("touch") })
  end
end
