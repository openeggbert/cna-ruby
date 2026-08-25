# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 34 — `System.Collections.ObjectModel.Collection`1` projects to
# `CNA::Runtime::Collection`.
#
# Every claim here is read back out of the measured BCL inventory Foundation 28 admitted rather than
# written down twice: the tests derive what to assert from `docs/generated/bcl-inventory.json`, so a
# projection that drifts from the IL fails even if this file is never touched again.
#
# The three decisions the measurement forces:
#
# 1. **A view that publishes mutation.** Same shape as the read-only sibling, opposite intent.
# 2. **Every mutation runs through a hook.** No Ruby-idiomatic mutation may exist beside the CLR
#    surface, because it would be a second path a subclass's hook never sees.
# 3. **Read-only belongs to the backing list.** Conditional here, unconditional there.
class CollectionTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  INVENTORY = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)

  CLR = "System.Collections.ObjectModel.Collection`1"
  READ_ONLY = "System.Collections.ObjectModel.ReadOnlyCollection`1"
  C = CNA::Runtime::Collection
  B = CNA::Runtime::BclProjection

  def measured = INVENTORY.fetch("types").fetch(CLR)

  def measured_member(name, access: nil)
    measured.fetch("members").find do |entry|
      entry.fetch("name") == name && (access.nil? || entry.fetch("access") == access)
    end
  end

  def behaviour(name) = measured_member(name).fetch("behaviour", {})

  def throws(name) = behaviour(name).fetch("throws", []).map { |entry| entry.fetch("exception") }

  # ------------------------------------------------------------------------------ the register

  def test_the_register_maps_it_to_the_support_class_and_not_to_an_array
    assert_equal "CNA::Runtime::Collection", B::TYPES.fetch(CLR)
    assert_equal C, Object.const_get(B::TYPES.fetch(CLR), false)
    assert_includes B.identities, CLR
    assert_equal 9, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_equal B::TYPES, STRICT.fetch("bclProjection").fetch("types")
    assert_equal B::TYPES.transform_keys(&:to_s),
                 RULES.fetch("bclProjection").fetch("types")

    assert_instance_of Class, C
    assert_equal Object, C.superclass
    refute_operator C, :<, ::Array
    refute_equal ::Array, C
    refute Object.const_defined?(:System, false)
    assert_equal CLR, C::CLR_IDENTITY
    assert_equal "CNA::Runtime::Collection", C.name
  end

  # It is the mutable sibling, not a second design: the two are separate classes with separate
  # measured surfaces and neither inherits from the other.
  def test_it_is_a_sibling_of_the_read_only_projection_not_a_subclass_of_it
    read_only = CNA::Runtime::ReadOnlyCollection
    refute_operator C, :<, read_only
    refute_operator read_only, :<, C
    refute_equal C, read_only
    assert_equal read_only.superclass, C.superclass

    # Both are still in the register, and the mutable one did not displace the other.
    assert_equal "CNA::Runtime::ReadOnlyCollection", B::TYPES.fetch(READ_ONLY)
    assert B.generic_projection?(CLR)
    assert B.generic_projection?(READ_ONLY)
  end

  def test_the_family_the_inventory_admitted_names_its_one_xna_consumer
    family = INVENTORY.fetch("families").find { |entry| entry.fetch("family") == CLR }
    refute_nil family
    assert_equal ["Microsoft.Xna.Framework.GameComponentCollection (base)"], family.fetch("xnaConsumers")
    assert_equal [CLR], family.fetch("types")
  end

  # ------------------------------------------------------------------- the surface is measured

  def test_every_measured_public_member_is_projected_and_nothing_else_is
    expected = measured.fetch("members").select do |entry|
      entry.fetch("access") == "public" && !entry.fetch("explicitInterface") &&
        entry.fetch("kind") == "method"
    end.map { |entry| entry.fetch("name") }

    projected = expected.map do |name|
      case name
      when "get_Count" then :Count
      when "get_Item" then :[]
      when "set_Item" then :[]=
      else name.to_sym
      end
    end.uniq

    assert_equal projected.sort, C::CLR_SURFACE.sort
    C::CLR_SURFACE.each { |identity| assert C.public_method_defined?(identity), identity }

    surface = C.public_instance_methods(false) - CNA::Runtime::LanguageSupport.identities
    assert_equal C::CLR_SURFACE.sort, surface.sort
  end

  def test_every_measured_family_member_is_projected_as_a_ruby_protected_member
    expected = measured.fetch("members").select do |entry|
      entry.fetch("access") == "family" && entry.fetch("kind") == "method"
    end.map { |entry| entry.fetch("name") == "get_Items" ? :Items : entry.fetch("name").to_sym }

    assert_equal expected.sort, C::CLR_PROTECTED_SURFACE.sort
    C::CLR_PROTECTED_SURFACE.each do |identity|
      assert C.protected_method_defined?(identity), identity
      refute C.public_method_defined?(identity), identity
    end
    assert_equal C::CLR_PROTECTED_SURFACE.sort, C.protected_instance_methods(false).sort
  end

  # The fourteen explicit interface implementations project to no member at all, exactly as
  # ReadOnlyCollection's twelve do. Ruby has no explicit interface implementation and this binding
  # fabricates no IList module, so there is nothing to call and nothing to throw from.
  def test_the_explicit_interface_implementations_project_to_nothing
    explicit = measured.fetch("members").select { |entry| entry.fetch("explicitInterface") }
    assert_equal 14, explicit.length
    assert_equal(%w[System.Collections.Generic.ICollection System.Collections.ICollection
                    System.Collections.IEnumerable System.Collections.IList].sort,
                 explicit.map { |entry| entry.fetch("name").sub(/\.[^.]+\z/, "").sub(/<T>\z/, "") }.uniq.sort)

    # Every one of them restates, under an interface-qualified name, an operation the public CLR
    # surface already carries -- or an interface-only flag. Ruby has no explicit interface
    # implementation, so the interface-only names exist nowhere on the projection and the shared
    # ones are reached through the CLR surface rather than through a fabricated interface.
    %i[IsReadOnly IsSynchronized SyncRoot IsFixedSize].each do |absent|
      refute C.method_defined?(absent), absent
      refute C.private_method_defined?(absent), absent
    end
    refute defined?(Microsoft::Xna::Framework::IList)
    refute CNA::Runtime.const_defined?(:IList, false)
  end

  # ---------------------------------------------------------- the two constructors are distinct

  def test_the_parameterless_constructor_creates_its_own_backing_list
    assert_equal 2, measured.fetch("members").count { |entry| entry.fetch("kind") == "constructor" }
    empty = measured.fetch("members").find do |entry|
      entry.fetch("kind") == "constructor" && entry.fetch("parameters").empty?
    end
    assert empty.fetch("behaviour").fetch("storesConstructorArgumentToField")
    assert_empty empty.fetch("behaviour").fetch("throws", [])

    collection = C.new
    assert_equal 0, collection.Count
    collection.Add(:a)
    assert_equal 1, collection.Count

    # Two instances never share a backing list.
    other = C.new
    assert_equal 0, other.Count
  end

  def test_the_list_constructor_refuses_null_naming_list_and_stores_the_reference
    listed = measured.fetch("members").find do |entry|
      entry.fetch("kind") == "constructor" && entry.fetch("parameters").length == 1
    end
    assert_equal ["System.ArgumentNullException"],
                 listed.fetch("behaviour").fetch("throws").map { |entry| entry.fetch("exception") }
    assert_equal "list", listed.fetch("behaviour").fetch("throws").first.fetch("argument")
    assert_equal "ArgumentError", B::THROWN_EXCEPTIONS.fetch("System.ArgumentNullException")

    error = assert_raises(ArgumentError) { C.new(nil) }
    assert_equal "list", error.message
    assert_raises(TypeError) { C.new("not a list") }
  end

  # A view, not a snapshot: the CLR stores the reference and copies nothing, then or later.
  def test_it_is_a_live_view_over_the_list_it_was_given
    backing = [1, 2, 3]
    collection = C.new(backing)
    assert_equal 3, collection.Count

    backing << 4
    assert_equal 4, collection.Count, "a mutation applied to the backing list is observable"
    assert_equal 4, collection[3]

    backing.shift
    assert_equal 3, collection.Count
    assert_equal 2, collection[0]

    refute backing.frozen?, "the projection must not freeze what it was given"
    refute_same backing, C.new(backing.dup).__send__(:Items)
    assert_same backing, collection.__send__(:Items)
  end

  # ------------------------------------------------------------------- every read forwards once

  def test_the_reads_forward_and_validate_nothing_of_their_own
    %w[get_Count get_Item CopyTo Contains GetEnumerator IndexOf].each do |name|
      assert_empty throws(name), name
      refute_nil behaviour(name)["delegatesTo"], name
    end

    collection = C.new([10, 20, 30])
    assert_equal 3, collection.Count
    assert_equal 20, collection[1]
    assert collection.Contains(30)
    refute collection.Contains(40)
    assert_equal 2, collection.IndexOf(30)
    assert_equal(-1, collection.IndexOf(40), "IndexOf answers -1 when absent, as the CLR does")

    destination = Array.new(4)
    collection.CopyTo(destination, 1)
    assert_equal [nil, 10, 20, 30], destination
  end

  def test_the_indexer_forwards_so_an_out_of_range_index_raises_index_error
    assert_equal "System.Collections.Generic.IList`1::get_Item", behaviour("get_Item").fetch("delegatesTo")
    collection = C.new([1, 2])
    assert_raises(IndexError) { collection[2] }
    assert_raises(IndexError) { collection[-1] }
    assert_raises(TypeError) { collection[nil] }
    assert_includes RULES.fetch("collections").fetch("indexErrors"), "IndexError"
  end

  # ---------------------------------------------------------------- every mutation runs a hook

  # This is the whole reason the type exists rather than List<T>: overriding one hook is enough to
  # observe every public mutation.
  def test_all_six_public_mutating_members_route_through_the_four_hooks
    trace = []
    subclass = Class.new(C) do
      define_method(:InsertItem) { |index, item| trace << [:InsertItem, index, item]; super(index, item) }
      define_method(:RemoveItem) { |index| trace << [:RemoveItem, index]; super(index) }
      define_method(:SetItem) { |index, item| trace << [:SetItem, index, item]; super(index, item) }
      define_method(:ClearItems) { trace << [:ClearItems]; super() }
    end

    collection = subclass.new
    collection.Add(:a)
    collection.Add(:b)
    collection.Insert(1, :c)
    collection[0] = :d
    collection.Remove(:c)
    collection.RemoveAt(0)
    collection.Clear

    assert_equal [
      [:InsertItem, 0, :a],
      [:InsertItem, 1, :b],
      [:InsertItem, 1, :c],
      [:SetItem, 0, :d],
      [:RemoveItem, 1],
      [:RemoveItem, 0],
      [:ClearItems]
    ], trace
    assert_equal 0, collection.Count
  end

  # Remove answers false without reaching the hook when IndexOf is negative.
  def test_removing_an_absent_item_answers_false_and_never_calls_the_hook
    calls = 0
    subclass = Class.new(C) { define_method(:RemoveItem) { |index| calls += 1; super(index) } }
    collection = subclass.new
    collection.Add(:a)

    refute collection.Remove(:missing)
    assert_equal 0, calls
    assert collection.Remove(:a)
    assert_equal 1, calls
    assert_equal 0, collection.Count
  end

  # Add's IL stores items.Count into a local before calling the hook, so the index the hook receives
  # is the one Add computed rather than the length the list has when the hook runs.
  def test_add_reads_count_once_before_the_hook
    seen = []
    subclass = Class.new(C) do
      define_method(:InsertItem) do |index, item|
        seen << index
        super(index, item)
        # A hook is free to mutate further; the index Add passed is already fixed.
        super(index, :"#{item}_extra") if item == :a
      end
    end
    collection = subclass.new
    collection.Add(:a)
    collection.Add(:b)
    assert_equal [0, 2], seen
  end

  # No Ruby-idiomatic mutation exists beside the CLR surface: any such member would be a second
  # path to the backing list that a subclass's hook never sees.
  def test_no_ruby_mutation_bypasses_the_hooks
    %i[<< push pop shift unshift delete delete_at delete_if concat replace clear insert
       []=  fill map! select! reject! sort! compact! flatten! uniq! keep_if append prepend].each do |name|
      next if name == :[]=

      refute C.public_method_defined?(name), "#{name} would bypass the hooks"
      refute C.protected_method_defined?(name), name
    end

    # `[]=` exists because the CLR declares set_Item, and it too runs through a hook.
    assert C.public_method_defined?(:[]=)
    routed = false
    subclass = Class.new(C) { define_method(:SetItem) { |i, v| routed = true; super(i, v) } }
    collection = subclass.new
    collection.Add(:a)
    collection[0] = :b
    assert routed
  end

  # -------------------------------------------------- read-only refusal, and its exact position

  def test_every_mutating_member_refuses_a_read_only_backing_list
    %w[set_Item Add Clear Insert Remove RemoveAt].each do |name|
      assert_includes throws(name), "System.NotSupportedException", name
      resource = behaviour(name).fetch("throws")
                                .find { |entry| entry.fetch("exception") == "System.NotSupportedException" }
      assert_equal "NotSupported_ReadOnlyCollection", resource.fetch("resource")
    end
    assert_equal "CNA::Runtime::NotSupportedError",
                 B::THROWN_EXCEPTIONS.fetch("System.NotSupportedException")

    frozen = C.new([1, 2, 3].freeze)
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.Add(4) }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.Clear }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.Insert(0, 4) }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.Remove(1) }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.RemoveAt(0) }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen[0] = 4 }

    # The reads are unaffected, because List<T> is never read-only and the reads never check.
    assert_equal 3, frozen.Count
    assert_equal 1, frozen[0]
    assert_equal [1, 2, 3], frozen.to_a
  end

  # The refusal is at IL offset 0 and the bound check is behind its branch, so the order is
  # observable exactly once: an out-of-range index on a frozen backing list.
  def test_the_read_only_refusal_comes_before_the_range_check
    frozen = C.new([1].freeze)
    assert_raises(CNA::Runtime::NotSupportedError) { frozen[99] = 2 }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.RemoveAt(99) }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.Insert(99, 2) }
    assert_raises(CNA::Runtime::NotSupportedError) { frozen.RemoveAt(-1) }

    mutable = C.new([1])
    assert_raises(RangeError) { mutable[99] = 2 }
    assert_raises(RangeError) { mutable.RemoveAt(99) }
    assert_raises(RangeError) { mutable.Insert(99, 2) }
  end

  # ------------------------------------------------- whoConstructsItDecides, inside one type

  def test_the_three_writers_construct_their_own_range_error_naming_index
    %w[set_Item Insert RemoveAt].each do |name|
      assert_includes throws(name), "System.ArgumentOutOfRangeException", name
    end
    assert_equal "RangeError", B::THROWN_EXCEPTIONS.fetch("System.ArgumentOutOfRangeException")

    collection = C.new([1, 2])
    [-1, 2, 99].each do |index|
      assert_equal "index", assert_raises(RangeError) { collection[index] = 0 }.message
      assert_equal "index", assert_raises(RangeError) { collection.RemoveAt(index) }.message
    end
    # Insert's upper bound is inclusive: Count itself is legal, Count + 1 is not.
    collection.Insert(2, 3)
    assert_equal [1, 2, 3], collection.to_a
    assert_equal "index", assert_raises(RangeError) { collection.Insert(4, 0) }.message
    assert_equal "index", assert_raises(RangeError) { collection.Insert(-1, 0) }.message
  end

  # Both halves of the rule on the same condition: reading answers IndexError, writing RangeError.
  def test_the_same_out_of_range_index_answers_differently_for_a_read_and_a_write
    collection = C.new([1, 2])
    assert_raises(IndexError) { collection[5] }
    assert_raises(RangeError) { collection[5] = 0 }
    assert_includes RULES.fetch("bclProjection").fetch("thrownExceptions").fetch("whoConstructsItDecides"),
                    "the projected member's own IL constructs"
    refute_operator RangeError, :<=, IndexError
    refute_operator IndexError, :<=, RangeError
  end

  # ------------------------------------------------------------------------- the enumerator

  def test_the_enumerator_walks_the_live_list_and_fails_fast
    collection = C.new
    [1, 2, 3].each { |value| collection.Add(value) }
    assert_equal [1, 2, 3], collection.GetEnumerator.to_a
    assert_equal [1, 2, 3], collection.each.to_a
    assert_instance_of Enumerator, collection.GetEnumerator
    assert_instance_of Enumerator, collection.each

    assert_raises(RuntimeError) { collection.each { collection.Add(9) } }
    assert_equal "RuntimeError", B::THROWN_EXCEPTIONS.fetch("System.InvalidOperationException")
  end

  # Stricter than the read-only projection, because this class owns every hook: replacing an element
  # in place trips the version counter, exactly as List<T>'s does.
  def test_replacing_an_element_in_place_trips_the_enumerator
    collection = C.new
    [1, 2, 3].each { |value| collection.Add(value) }
    assert_raises(RuntimeError) { collection.each { collection[0] = 9 } }

    read_only = CNA::Runtime::ReadOnlyCollection.new([1, 2, 3])
    assert_equal [1, 2, 3], read_only.each.to_a
  end

  def test_a_length_change_through_the_callers_own_reference_is_caught_too
    backing = [1, 2, 3]
    collection = C.new(backing)
    assert_raises(RuntimeError) { collection.each { backing.pop } }
  end

  # ------------------------------------------------- language support is admitted by rule only

  def test_each_is_language_support_and_carries_get_enumerator
    assert_equal "GetEnumerator", CNA::Runtime::LanguageSupport.derived_from(:each)
    assert_includes C::LANGUAGE_SUPPORT, :each
    assert_includes C.ancestors, ::Enumerable
    assert_includes C::CLR_SURFACE, :GetEnumerator

    # Enumerable is derived from `each` alone, so it adds no independent behaviour.
    collection = C.new([3, 1, 2])
    assert_equal [1, 2, 3], collection.sort
    assert_equal 3, collection.max
    assert_equal [3, 1, 2], collection.to_a
  end

  # --------------------------------------------------------- the generic element metadata rule

  class CorrectFixture < CNA::Runtime::Collection
    projects_elements "Microsoft.Xna.Framework.IGameComponent"
  end

  class UndeclaredFixture < CNA::Runtime::Collection; end

  class WrongElementFixture < CNA::Runtime::Collection
    projects_elements "Microsoft.Xna.Framework.GameComponent"
  end

  class ReadOnlySiblingFixture < CNA::Runtime::ReadOnlyCollection
    projects_elements "Microsoft.Xna.Framework.IGameComponent"
  end

  class ArrayFixture < ::Array; end
  class ObjectFixture; end

  def contracts(ruby_name, base:)
    type = {
      "name" => "Microsoft.Xna.Framework.FixtureCollection", "rubyName" => ruby_name,
      "kind" => "class", "flags" => false, "baseType" => base, "interfaces" => [],
      "directInterfaces" => [], "genericParameters" => [], "members" => []
    }
    [{"types" => [Marshal.load(Marshal.dump(type))]}, {"types" => [Marshal.load(Marshal.dump(type))]}]
  end

  def diagnostics(ruby_name, base: "#{CLR}[Microsoft.Xna.Framework.IGameComponent]")
    reference, target = contracts(ruby_name, base: base)
    CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify.counts
  end

  def test_a_correct_bcl_generic_base_is_accepted
    counts = diagnostics("CollectionTest::CorrectFixture")
    assert_equal 0, counts.fetch("BASE_MAPPING_MISMATCH")
    assert_equal 0, counts.fetch("GENERIC_MAPPING_MISMATCH")
    assert_equal ["Microsoft.Xna.Framework.IGameComponent"], CorrectFixture.clr_element_types
  end

  def test_mutation_array_substitution_for_the_bcl_base
    assert_operator diagnostics("CollectionTest::ArrayFixture").fetch("BASE_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_object_fallback_for_the_bcl_base
    assert_operator diagnostics("CollectionTest::ObjectFixture").fetch("BASE_MAPPING_MISMATCH"), :>, 0
  end

  # The mutable and read-only projections are not interchangeable: substituting one for the other is
  # a base mismatch in both directions.
  def test_mutation_the_read_only_sibling_substituted_for_the_mutable_base
    assert_operator diagnostics("CollectionTest::ReadOnlySiblingFixture").fetch("BASE_MAPPING_MISMATCH"), :>, 0
    assert_operator diagnostics("CollectionTest::CorrectFixture",
                                base: "#{READ_ONLY}[Microsoft.Xna.Framework.IGameComponent]")
                      .fetch("BASE_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_the_support_class_itself_without_element_metadata
    counts = diagnostics("CollectionTest::UndeclaredFixture")
    assert_equal 0, counts.fetch("BASE_MAPPING_MISMATCH"), "the Ruby base is right"
    assert_operator counts.fetch("GENERIC_MAPPING_MISMATCH"), :>, 0, "but the element projection is missing"
    assert_nil UndeclaredFixture.clr_element_types
  end

  def test_mutation_the_wrong_generic_element_projection
    assert_operator diagnostics("CollectionTest::WrongElementFixture").fetch("GENERIC_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_a_fabricated_system_namespace_cannot_resolve
    refute Object.const_defined?(:System, false)
    assert_raises(NameError) do
      "System::Collections::ObjectModel::Collection"
        .split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
    end
    B::TYPES.each_value { |path| refute path.start_with?("System::"), path }
  end

  # ------------------------------------------------------------------------ the strict scoreboard

  def test_the_projection_moves_no_structural_diagnostic
    assert_equal 0, STRICT.fetch("GENERIC_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("BASE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("LANGUAGE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("UNMEASURED_STRUCTURAL_CATEGORY")
    assert_equal 0, STRICT.fetch("ALLOWLIST_ENTRIES")
    assert_includes FRONTIER.fetch("mappedBclTypes"), CLR
  end
end
