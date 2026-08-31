# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 46 — `Dictionary`2` and `LaunchParameters`.
#
# The last purely-decisional BCL blocker, and the XNA type it was blocking. Every behaviour asserted
# here is read out of the admitted Microsoft .NET Framework 4.0 mscorlib (SHA-256 `5634668d…`) and
# the pinned `Microsoft.Xna.Framework.Game.dll` (SHA-256 `b5dffdd8…`), never from memory and never
# from a modern .NET or Mono reimplementation.
class DictionaryTest < Minitest::Test
  D = CNA::Runtime::Dictionary
  B = CNA::Runtime::BclProjection
  F = Microsoft::Xna::Framework
  CLR = "System.Collections.Generic.Dictionary`2"
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(
    ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read
  ).fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
                   .fetch("types").to_h { |type| [type.fetch("name"), type] }.freeze
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read).freeze

  # ------------------------------------------------------------------------------- the register

  def test_the_register_maps_it_to_the_support_class_and_not_to_a_hash
    assert_equal "CNA::Runtime::Dictionary", B::TYPES.fetch(CLR)
    assert_equal D, Object.const_get(B::TYPES.fetch(CLR), false)
    assert_includes B.identities, CLR
    assert_equal 11, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_equal B::TYPES.transform_keys(&:to_s), RULES.fetch("bclProjection").fetch("types")

    # It is a class of its own, not any of the shapes a reader might reach for first.
    assert_instance_of Class, D
    assert_equal Object, D.superclass
    refute_operator D, :<, ::Hash
  end

  # `get_Item` throws where `Hash#[]` answers nil, `Add` throws where `Hash#store` overwrites, and
  # `Hash#each` never fails fast — which is exactly why a Hash is the store and not the projection.
  def test_it_is_not_a_hash_wearing_clr_names
    dictionary = D.new
    dictionary.Add("k", "v")
    refute_respond_to dictionary, :store
    assert_raises(::KeyError) { dictionary["absent"] }
    assert_raises(ArgumentError) { dictionary.Add("k", "w") }
  end

  def test_key_not_found_is_a_measured_thrown_exception
    assert_equal "KeyError", B::THROWN_EXCEPTIONS.fetch("System.Collections.Generic.KeyNotFoundException")
    assert_equal 7, STRICT.fetch("BCL_THROWN_EXCEPTIONS")
    assert_operator ::KeyError, :<, ::StandardError
    refute_operator ::KeyError, :<, ::ScriptError
    documented = RULES.fetch("bclProjection").fetch("thrownExceptions")
    assert_includes documented.fetch("System.Collections.Generic.KeyNotFoundException"), "KeyError"
    # A thrown exception is never an identity the XNA surface names.
    refute_includes B.identities, "System.Collections.Generic.KeyNotFoundException"
  end

  # ------------------------------------------------------------------------- the measured surface

  # Twenty-two of the CLR type's methods are explicit interface implementations, which project to
  # nothing, and its SerializationInfo constructor is `family`. What is left is this.
  def test_the_projected_surface_is_the_ordinary_public_one
    expected = %i[Comparer Count Keys Values [] []= Add Clear ContainsKey ContainsValue
                  GetEnumerator Remove TryGetValue GetObjectData OnDeserialization]
    expected.each { |name| assert D.public_method_defined?(name), name }
    # No Ruby-idiomatic second way to mutate exists beside the CLR surface. `Collection` refuses a
    # `<<` for the same reason: a second entry point is one a subclass's override never sees.
    %i[store merge merge! delete delete_if fetch each_pair update << push].each do |absent|
      refute D.public_method_defined?(absent), "#{absent} is not a CLR identity"
    end
  end

  def test_count_add_and_the_indexer
    dictionary = D.new
    assert_equal 0, dictionary.Count
    assert_nil dictionary.Add("a", "1")
    dictionary.Add("b", "2")
    assert_equal 2, dictionary.Count
    assert_equal "1", dictionary["a"]
    # set_Item is Insert(add: false): it replaces rather than refusing.
    dictionary["a"] = "9"
    assert_equal "9", dictionary["a"]
    assert_equal 2, dictionary.Count
  end

  # `Insert` opens with `ThrowArgumentNullException(ExceptionArgument.key)` before anything else,
  # and every keyed member shares that check.
  def test_a_null_key_is_refused_by_every_keyed_member
    dictionary = D.new
    assert_raises(ArgumentError) { dictionary.Add(nil, "v") }
    assert_raises(ArgumentError) { dictionary[nil] = "v" }
    assert_raises(ArgumentError) { dictionary[nil] }
    assert_raises(ArgumentError) { dictionary.ContainsKey(nil) }
    assert_raises(ArgumentError) { dictionary.Remove(nil) }
    assert_raises(ArgumentError) { dictionary.TryGetValue(nil) }
  end

  # A null *value* is ordinary, and `ContainsValue`'s null branch answers without a comparer.
  def test_a_null_value_is_stored_and_found
    dictionary = D.new
    dictionary.Add("k", nil)
    assert_nil dictionary["k"]
    assert dictionary.ContainsValue(nil)
    assert dictionary.ContainsKey("k")
    refute dictionary.ContainsValue("anything")
  end

  def test_contains_key_contains_value_and_try_get_value
    dictionary = D.new
    dictionary.Add("k", "v")
    assert dictionary.ContainsKey("k")
    refute dictionary.ContainsKey("absent")
    assert dictionary.ContainsValue("v")
    refute dictionary.ContainsValue("absent")
    assert_equal "v", dictionary.TryGetValue("k")
    assert_nil dictionary.TryGetValue("absent")
  end

  # `Remove` answers false for an absent key **without** touching the version, and true when an
  # entry really goes.
  def test_remove_answers_a_boolean_and_only_bumps_the_version_when_it_removes
    dictionary = D.new
    dictionary.Add("k", "v")
    before = version_of(dictionary)
    refute dictionary.Remove("absent")
    assert_equal before, version_of(dictionary)
    assert dictionary.Remove("k")
    assert_equal before + 1, version_of(dictionary)
    assert_equal 0, dictionary.Count
  end

  # Measured, not assumed: `Clear` returns at `ldfld count; ldc.i4.0; ble.s` straight to `ret`, so
  # clearing an empty dictionary does not invalidate an enumeration in flight.
  def test_clearing_an_empty_dictionary_does_not_bump_the_version
    empty = D.new
    before = version_of(empty)
    empty.Clear
    assert_equal before, version_of(empty)

    populated = D.new
    populated.Add("k", "v")
    before = version_of(populated)
    populated.Clear
    assert_equal before + 1, version_of(populated)
    assert_equal 0, populated.Count
  end

  # ------------------------------------------------------------------------------ the views

  # `KeyCollection` and `ValueCollection` store one reference to the dictionary and forward. They
  # are views, not snapshots, so an Add after the view was taken is visible through it.
  def test_keys_and_values_are_live_views
    dictionary = D.new
    dictionary.Add("a", "1")
    keys = dictionary.Keys
    values = dictionary.Values
    assert_equal 1, keys.Count
    dictionary.Add("b", "2")
    assert_equal 2, keys.Count
    assert_equal %w[a b], keys.to_a
    assert_equal %w[1 2], values.to_a
  end

  # Their whole public surface in the pinned IL is four members, and every mutating member each
  # declares is an explicit interface implementation that throws. So none exists here.
  def test_the_views_declare_no_mutation
    view = D.new.Keys
    %i[Add Remove Clear []= push << delete].each do |absent|
      refute view.respond_to?(absent), absent
    end
    assert_respond_to view, :Count
    assert_respond_to view, :CopyTo
    assert_respond_to view, :GetEnumerator
  end

  def test_view_copy_to_validates_then_writes_in_enumeration_order
    dictionary = D.new
    dictionary.Add("a", "1")
    dictionary.Add("b", "2")
    destination = Array.new(4)
    dictionary.Keys.CopyTo(destination, 1)
    assert_equal [nil, "a", "b", nil], destination
    assert_raises(ArgumentError) { dictionary.Keys.CopyTo(nil, 0) }
    assert_raises(RangeError) { dictionary.Keys.CopyTo(Array.new(4), -1) }
    assert_raises(ArgumentError) { dictionary.Keys.CopyTo(Array.new(1), 0) }
  end

  # ------------------------------------------------------------------------ fail-fast enumeration

  def test_enumeration_fails_fast_on_a_mutation
    dictionary = D.new
    dictionary.Add("a", "1")
    enumerator = dictionary.GetEnumerator
    dictionary.Add("b", "2")
    assert_raises(::RuntimeError) { enumerator.to_a }
  end

  # The nested enumerators read the dictionary's own version field, so a mutation invalidates a key
  # or value traversal too.
  def test_view_enumeration_fails_fast_on_the_same_counter
    dictionary = D.new
    dictionary.Add("a", "1")
    keys = dictionary.Keys.GetEnumerator
    values = dictionary.Values.GetEnumerator
    dictionary.Remove("a")
    assert_raises(::RuntimeError) { keys.to_a }
    assert_raises(::RuntimeError) { values.to_a }
  end

  def test_the_enumerator_yields_key_value_pairs
    dictionary = D.new
    dictionary.Add("a", "1")
    dictionary.Add("b", "2")
    assert_equal [%w[a 1], %w[b 2]], dictionary.GetEnumerator.to_a
    assert_equal [%w[a 1], %w[b 2]], dictionary.to_a
  end

  # ------------------------------------------------------------------------------- the comparer

  # `EqualityComparer<TKey>.Default` is the key's own equality, which is Ruby's own, so the default
  # projects to nil rather than to an invented object claiming a CLR identity.
  def test_the_default_comparer_is_nil
    assert_nil D.new.Comparer
  end

  # `IEqualityComparer<T>`'s whole contract is `Equals(a, b)` and `GetHashCode(x)`, so a duck type
  # answering those two is the narrowest reusable projection the interface admits.
  def test_a_supplied_comparer_decides_equality_hashing_and_duplicates
    comparer = Object.new
    def comparer.Equals(left, right) = left.to_s.downcase == right.to_s.downcase
    def comparer.GetHashCode(value) = value.to_s.downcase.hash

    dictionary = D.new(comparer: comparer)
    dictionary.Add("Key", "v")
    assert_same comparer, dictionary.Comparer
    assert dictionary.ContainsKey("KEY")
    assert_equal "v", dictionary["kEy"]
    assert_raises(ArgumentError) { dictionary.Add("KEY", "w") }
    assert dictionary.Remove("keY")
    assert_equal 0, dictionary.Count
  end

  # ---------------------------------------------------------------------------- the constructors

  def test_capacity_is_validated_rather_than_silently_ignored
    assert_equal 0, D.new(capacity: 16).Count
    assert_raises(RangeError) { D.new(capacity: -1) }
    assert_raises(TypeError) { D.new(capacity: "16") }
  end

  # `.ctor(IDictionary<K,V>)` copies through `Add`, so a duplicate under the supplied comparer
  # raises exactly as `Add` would rather than being silently collapsed.
  def test_a_seeded_dictionary_copies_through_add
    source = D.new
    source.Add("a", "1")
    copy = D.new(source)
    assert_equal 1, copy.Count
    assert_equal "1", copy["a"]
    source.Add("b", "2")
    assert_equal 1, copy.Count, "the copy is not a view"

    comparer = Object.new
    def comparer.Equals(left, right) = left.to_s.downcase == right.to_s.downcase
    def comparer.GetHashCode(value) = value.to_s.downcase.hash
    clashing = D.new
    clashing.Add("a", "1")
    clashing.Add("A", "2")
    assert_raises(ArgumentError) { D.new(clashing, comparer: comparer) }
  end

  # ------------------------------------------------------------------------------- serialization

  # `GetObjectData` and `OnDeserialization` are public members of the CLR type, so they are carried.
  # Neither needs a formatter runtime: the contract is "hand your state to this carrier" and "take
  # it back", and the carrier is a plain named-value bag. No formatter, surrogate selector, binder
  # or stream format is invented, and `SerializationInfo` is deliberately not a projected identity.
  def test_get_object_data_and_on_deserialization_round_trip_through_a_carrier
    carrier = Class.new do
      def initialize = @values = {}
      def AddValue(name, value) = @values[name] = value
      def GetValue(name) = @values[name]
    end.new

    dictionary = D.new
    dictionary.Add("a", "1")
    dictionary.Add("b", "2")
    dictionary.GetObjectData(carrier)
    assert_equal [%w[a 1], %w[b 2]], carrier.GetValue("KeyValuePairs")
    assert_nil carrier.GetValue("Comparer")

    restored = D.new
    restored.OnDeserialization(nil, info: carrier)
    assert_equal 2, restored.Count
    assert_equal "2", restored["b"]

    assert_raises(ArgumentError) { dictionary.GetObjectData(nil) }
    refute_includes B.identities, "System.Runtime.Serialization.SerializationInfo"
  end

  # ------------------------------------------------------------------------------ LaunchParameters

  def test_the_pinned_contract_is_one_member_over_a_dictionary_base
    reference = REFERENCE.fetch("Microsoft.Xna.Framework.LaunchParameters")
    assert_equal "class", reference.fetch("kind")
    assert_equal "System.Collections.Generic.Dictionary`2[System.String,System.String]",
                 reference.fetch("baseType")
    assert_empty reference.fetch("directInterfaces")
    assert_equal 10, reference.fetch("interfaces").length
    assert_equal [%w[constructor .ctor]],
                 reference.fetch("members").map { |member| [member.fetch("kind"), member.fetch("name")] }
    assert_equal reference.fetch("interfaces"),
                 SIGNATURES.fetch("Microsoft.Xna.Framework.LaunchParameters").fetch("interfaces")
  end

  def test_the_clr_base_relationship_survives_with_its_type_arguments
    assert_equal D, F::LaunchParameters.superclass
    assert_equal %w[System.String System.String], F::LaunchParameters.clr_element_types
    assert_equal 0, STRICT.fetch("BASE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("GENERIC_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("INTERFACE_MAPPING_MISMATCH")
    refute_includes STRICT.fetch("missingTypeNames"), "Microsoft.Xna.Framework.LaunchParameters"
  end

  # The whole public surface is inherited: the type declares one constructor and nothing else, and
  # its two parsing helpers are `assembly` and `private`, so neither is an identity.
  def test_it_declares_no_member_of_its_own
    own = F::LaunchParameters.public_instance_methods(false)
    assert_empty own, own.inspect
    %i[ParseCommandLineArguments ParseKeyValuePair].each do |internal|
      refute F::LaunchParameters.public_method_defined?(internal), internal
    end
  end

  # `ParseCommandLineArguments`'s exact loop, argument by argument.
  def test_the_parse_is_the_pinned_one
    parameters = F::LaunchParameters.new(
      ["-windowed", "/res:1920x1080", "-res:800x600", "--verbose", "x:a:b", ":", "-", ""]
    )
    assert_equal 4, parameters.Count
    # A colonless argument is KEPT with String.Empty as its value; it is not skipped.
    assert_equal "", parameters["windowed"]
    assert_equal "", parameters["verbose"]
    # Both `/` and `-` are trimmed, and TrimStart removes a run of them.
    assert parameters.ContainsKey("verbose")
    # The FIRST occurrence of a name wins, because the guard is ContainsKey and the write is Add.
    assert_equal "1920x1080", parameters["res"]
    # IndexOf(char) finds the FIRST colon, so a value keeps any later ones.
    assert_equal "a:b", parameters["x"]
    # An empty key is skipped: ":" splits to an empty key, and "-" and "" trim to nothing.
    refute parameters.ContainsKey("")
  end

  def test_an_empty_argument_list_yields_an_empty_map
    assert_equal 0, F::LaunchParameters.new([]).Count
  end

  # `Environment.GetCommandLineArgs()` includes the executable path at index 0 and XNA's loop starts
  # at 1; Ruby's ARGV already excludes it, so the default is exact.
  def test_the_default_argument_source_is_argv
    assert_equal F::LaunchParameters.new(::ARGV).GetEnumerator.to_a,
                 F::LaunchParameters.new.GetEnumerator.to_a
  end

  # ------------------------------------------------------------------------------ Game.LaunchParameters

  # `get_LaunchParameters` is one `ldfld`: the same object for the life of the Game, created by the
  # constructor, and it needs no native host.
  def test_game_answers_the_same_object_and_creates_no_host
    game = F::Game.new
    begin
      parameters = game.LaunchParameters
      assert_instance_of F::LaunchParameters, parameters
      assert_same parameters, game.LaunchParameters
      assert_nil game.instance_variable_get(:@host)
      refute(STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
                   .any? { |entry| entry.include?("::LaunchParameters") })
    ensure
      game.Dispose
    end
  end

  # The canonical CNA launch-parameter routes exist and are deliberately unbound: audited against
  # the pinned IL they implement different semantics on three counts the inherited dictionary
  # surface makes observable.
  def test_the_cna_launch_parameter_routes_are_deliberately_not_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    refute(symbols.any? { |symbol| symbol.include?("launch_parameters") }, symbols.inspect)
    assert_equal 55, CNA::Native::Manifest::FUNCTIONS.length
  end

  private

  def version_of(dictionary) = dictionary.instance_variable_get(:@version)
end
