# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 29 — `System.Collections.ObjectModel.ReadOnlyCollection`1` projects to
# `CNA::Runtime::ReadOnlyCollection`.
#
# Every claim here is read back out of the measured BCL inventory Foundation 28 admitted rather than
# written down twice: the tests derive what to assert from `docs/generated/bcl-inventory.json`, so a
# projection that drifts from the IL fails even if this file is never touched again.
#
# The two decisions the measurement forces:
#
# 1. **A view, not a snapshot.** The CLR constructor stores the `IList<T>` reference and every
#    public read member forwards one call to it. A frozen Ruby Array would be a different type.
# 2. **Read-only is a property of the interface.** Twelve mutating members are explicit interface
#    implementations whose whole body throws. Ruby has no explicit interface implementation, so the
#    projection of "the caller cannot mutate through this interface" is that no mutating member
#    exists at all.
class ReadOnlyCollectionTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  INVENTORY = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)
  RULES = JSON.parse(ROOT.join("tools", "api_compat", "mapping-rules.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  FRONTIER = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)

  CLR = "System.Collections.ObjectModel.ReadOnlyCollection`1"
  R = CNA::Runtime::ReadOnlyCollection
  B = CNA::Runtime::BclProjection

  def measured = INVENTORY.fetch("types").fetch(CLR)

  def measured_member(name)
    measured.fetch("members").find { |entry| entry.fetch("name") == name }
  end

  # ------------------------------------------------------------------------------ the register

  def test_the_register_maps_it_to_the_support_class_and_not_to_an_array
    assert_equal "CNA::Runtime::ReadOnlyCollection", B::TYPES.fetch(CLR)
    assert_equal R, Object.const_get(B::TYPES.fetch(CLR), false)
    assert_includes B.identities, CLR
    assert_equal ReviewedScoreboard::BCL_PROJECTED_IDENTITIES, STRICT.fetch("BCL_PROJECTED_IDENTITIES")
    assert_equal B::TYPES, STRICT.fetch("bclProjection").fetch("types")

    # It is a class of its own, not any of the shapes that were plausible before it was measured.
    assert_instance_of Class, R
    assert_equal Object, R.superclass
    refute_operator R, :<, ::Array
    refute_equal ::Array, R
    refute_equal ::Set, R if defined?(::Set)
    refute Object.const_defined?(:System, false)
    assert_equal CLR, R::CLR_IDENTITY

    # And it left the not-yet-designed list without dragging anything else off it.
    refute_includes RULES.fetch("bclProjection").fetch("notYetDesigned"), CLR
    # Foundation 33 took System.Type and System.IServiceProvider off this list.
    assert_equal ["System.IO.Stream", "System.Text.StringBuilder",
                  "System.Runtime.Serialization.SerializationInfo",
                  "System.Collections.Generic.Dictionary`2"],
                 RULES.fetch("bclProjection").fetch("notYetDesigned")
  end

  def test_one_register_entry_answers_for_every_constructed_form
    %W[#{CLR}[System.Char] #{CLR}[System.Single]
       #{CLR}[Microsoft.Xna.Framework.Graphics.GraphicsAdapter]].each do |constructed|
      assert_equal CLR, B.definition(constructed)
      assert_equal "CNA::Runtime::ReadOnlyCollection", B.ruby_type(constructed)
      assert B.generic_projection?(constructed), constructed
    end
    assert_equal ["Microsoft.Xna.Framework.Graphics.ModelBone"],
                 B.element_types("#{CLR}[Microsoft.Xna.Framework.Graphics.ModelBone]")
    assert_equal %w[System.String System.String],
                 B.element_types("System.Collections.Generic.Dictionary`2[System.String,System.String]")
    assert_empty B.element_types("System.EventArgs")
    refute B.generic_projection?("System.EventArgs")
  end

  # ------------------------------------------------------------------- the measured public surface

  def test_the_projected_surface_is_exactly_the_measured_clr_surface
    expected = measured.fetch("members")
                       .select { |entry| entry.fetch("access") == "public" && entry.fetch("kind") != "property" }
                       .map { |entry| entry.fetch("name") }
    assert_equal %w[.ctor Contains CopyTo GetEnumerator IndexOf get_Count get_Item], expected.sort

    # get_Count is the Count property's getter and get_Item is the indexer's; the CLR property
    # identities are what the Ruby surface carries, under the rules already in mapping-rules.json.
    assert_equal %i[Count [] Contains CopyTo GetEnumerator IndexOf].sort, R::CLR_SURFACE.sort
    R::CLR_SURFACE.each { |identity| assert R.public_method_defined?(identity), identity }
    assert_equal %i[Items], R::CLR_PROTECTED_SURFACE
    assert R.protected_method_defined?(:Items)
    refute R.public_method_defined?(:Items)

    # Every declared identity is one of the two sets, and nothing else is public.
    declared = R.public_instance_methods(false) + R.protected_instance_methods(false)
    assert_equal (R::CLR_SURFACE + R::CLR_PROTECTED_SURFACE + [:each]).sort, declared.sort
  end

  # The CLR surface and the Ruby language support can never be confused, because one is PascalCase
  # or an operator and the other is not.
  def test_language_support_is_separable_from_the_clr_surface
    assert_includes R::LANGUAGE_SUPPORT, :each
    assert_includes R::LANGUAGE_SUPPORT, :map
    assert_includes R::LANGUAGE_SUPPORT, :select
    assert_empty(R::CLR_SURFACE & R::LANGUAGE_SUPPORT)
    assert_empty(R::CLR_PROTECTED_SURFACE & R::LANGUAGE_SUPPORT)
    R::CLR_SURFACE.each do |identity|
      assert(identity == :[] || identity.to_s.match?(/\A[A-Z]/), identity)
    end
    R::LANGUAGE_SUPPORT.each { |identity| refute identity.to_s.match?(/\A[A-Z]/), identity }

    # Enumerable is derived in its entirety from `each`, which is the single Ruby identity carrying
    # CLR GetEnumerator, so including it adds no independent behaviour to measure.
    assert_operator R, :<, ::Enumerable
    assert_equal (::Enumerable.instance_methods + [:each]).sort.uniq, R::LANGUAGE_SUPPORT.sort
    assert_includes RULES.fetch("bclProjection").fetch("languageSupport"), "not XNA identities"
  end

  # ------------------------------------------------------------------------ view, not a snapshot

  def test_the_constructor_stores_the_reference_the_way_the_il_does
    facts = measured_member(".ctor").fetch("behaviour")
    assert facts.fetch("storesConstructorArgumentToField")
    assert_equal "System.ArgumentNullException", facts.fetch("throws").first.fetch("exception")
    assert_equal "list", facts.fetch("throws").first.fetch("argument")

    backing = [1, 2, 3]
    view = R.new(backing)
    assert_same backing, view.__send__(:Items)
    refute backing.frozen?, "a frozen copy would be a different type"

    error = assert_raises(ArgumentError) { R.new(nil) }
    assert_equal "list", error.message
    assert_raises(TypeError) { R.new("not a list") }
    assert_raises(TypeError) { R.new(1..3) }
  end

  def test_backing_mutation_is_observable_through_the_wrapper
    backing = %w[a b]
    view = R.new(backing)
    assert_equal 2, view.Count
    assert_equal "a", view[0]

    backing << "c"
    assert_equal 3, view.Count, "Count forwards to the backing list rather than a snapshot"
    assert_equal "c", view[2]
    assert view.Contains("c")
    assert_equal 2, view.IndexOf("c")

    backing[0] = "z"
    assert_equal "z", view[0]

    backing.clear
    assert_equal 0, view.Count
    assert_equal(-1, view.IndexOf("z"))
  end

  # Every public read member is a forward, and the inventory says to which member of which
  # interface. Nothing here is written down twice.
  def test_every_public_read_member_forwards_to_the_backing_list
    {
      "get_Count" => "System.Collections.Generic.ICollection`1::get_Count",
      "get_Item" => "System.Collections.Generic.IList`1::get_Item",
      "Contains" => "System.Collections.Generic.ICollection`1::Contains",
      "CopyTo" => "System.Collections.Generic.ICollection`1::CopyTo",
      "GetEnumerator" => "System.Collections.Generic.IEnumerable`1::GetEnumerator",
      "IndexOf" => "System.Collections.Generic.IList`1::IndexOf"
    }.each do |name, target|
      facts = measured_member(name).fetch("behaviour")
      assert_equal target, facts.fetch("delegatesTo"), name
      assert_equal "list", facts.fetch("viaField"), name
      refute facts.key?("throws"), "#{name} validates nothing of its own"
    end
  end

  # ---------------------------------------------------------------------- read-only, measured

  def test_no_mutating_member_exists_at_all
    mutators = measured.fetch("members").select do |entry|
      entry.fetch("behaviour", {}).fetch("throws", []).any? do |throw|
        throw.fetch("exception") == "System.NotSupportedException"
      end
    end
    assert_equal 12, mutators.length
    mutators.each do |entry|
      assert entry.fetch("explicitInterface"), entry.fetch("name")
      assert entry.fetch("behaviour").fetch("throwsUnconditionally"), entry.fetch("name")
    end

    view = R.new([1, 2, 3])
    %i[Add Clear Insert Remove RemoveAt []= Item= push << concat delete clear
       insert unshift pop shift].each do |mutating|
      refute view.respond_to?(mutating), mutating
    end
    # Nothing on the class declares a writer either.
    assert_empty R.instance_methods.grep(/=\z/) - Object.instance_methods
  end

  # ------------------------------------------------------------------------- measured behaviour

  def test_count_and_the_indexer
    view = R.new([10, 20, 30])
    assert_equal 3, view.Count
    assert_equal 10, view[0]
    assert_equal 30, view[2]
  end

  # The wrapper adds no bounds condition, so these are the backing list's, read through the
  # IList<T> contract mapping-rules.json records: out of range raises, and a negative index is out
  # of range rather than counting from the end, exactly as CurveKeyCollection already behaves.
  def test_the_indexer_bounds_follow_the_binding_wide_ilist_rule
    view = R.new([10, 20, 30])
    assert_raises(IndexError) { view[3] }
    assert_raises(IndexError) { view[-1] }
    assert_raises(IndexError) { R.new([])[0] }
    assert_raises(TypeError) { view[nil] }
    assert_raises(TypeError) { view["0"] }
    assert_raises(TypeError) { view[1.0] }
    assert_raises(RangeError) { view[2**31] }
    assert_includes RULES.fetch("collections").fetch("indexErrors"), "IndexError"

    # The Ruby Array answer for the same reads, which this deliberately is not.
    assert_nil [10, 20, 30][3]
    assert_equal 30, [10, 20, 30][-1]
  end

  def test_contains_and_index_of
    view = R.new(%w[a b c b])
    assert view.Contains("b")
    refute view.Contains("z")
    assert_equal 1, view.IndexOf("b"), "the first occurrence, as IList<T>.IndexOf answers"
    assert_equal(-1, view.IndexOf("z"), "absent answers -1, not nil")
    assert_equal 0, view.IndexOf("a")
    refute R.new([]).Contains(nil)
    assert_equal(-1, R.new([]).IndexOf(nil))
  end

  def test_copy_to_writes_into_the_destination_from_the_offset
    view = R.new([1, 2, 3])
    destination = Array.new(5, :untouched)
    assert_nil view.CopyTo(destination, 1)
    assert_equal [:untouched, 1, 2, 3, :untouched], destination

    assert_raises(ArgumentError) { view.CopyTo(nil, 0) }
    assert_raises(TypeError) { view.CopyTo("no", 0) }
    assert_raises(TypeError) { view.CopyTo(destination, nil) }
    assert_raises(IndexError) { view.CopyTo(destination, -1) }
    assert_raises(ArgumentError) { view.CopyTo(destination, 3) }
    assert_raises(ArgumentError) { view.CopyTo(Array.new(2), 0) }
    # An exactly-fitting destination is accepted.
    exact = Array.new(3)
    assert_nil view.CopyTo(exact, 0)
    assert_equal [1, 2, 3], exact
  end

  # ---------------------------------------------------------------------------- enumeration

  def test_get_enumerator_answers_a_fresh_ruby_enumerator_over_the_live_list
    backing = [1, 2, 3]
    view = R.new(backing)
    enumerator = view.GetEnumerator
    assert_instance_of Enumerator, enumerator
    refute_same enumerator, view.GetEnumerator
    assert_equal [1, 2, 3], enumerator.to_a

    # Live: a fresh enumerator sees a later mutation of the backing list.
    backing << 4
    assert_equal [1, 2, 3, 4], view.GetEnumerator.to_a
  end

  def test_each_is_the_iteration_primitive_and_carries_get_enumerator
    view = R.new(%w[a b])
    seen = []
    assert_same view, view.each { |item| seen << item }
    assert_equal %w[a b], seen
    assert_instance_of Enumerator, view.each
    assert_equal %w[a b], view.each.to_a

    # Everything Enumerable contributes is derived from that one identity.
    assert_equal %w[A B], view.map(&:upcase)
    assert_equal ["b"], view.select { |item| item == "b" }
    assert_equal %w[a b], view.to_a
    assert_equal 2, view.count
    assert view.include?("a")
  end

  def test_enumeration_fails_fast_when_the_backing_list_changes_length
    backing = [1, 2, 3]
    view = R.new(backing)
    error = assert_raises(RuntimeError) do
      view.each { |_item| backing << 99 }
    end
    assert_equal "the backing collection was modified during enumeration", error.message

    shrinking = [1, 2, 3]
    assert_raises(RuntimeError) { R.new(shrinking).each { shrinking.pop } }
  end

  # --------------------------------------------------------- the generic element metadata rule

  class BoneFixture; end

  class CorrectFixture < CNA::Runtime::ReadOnlyCollection
    projects_elements "Microsoft.Xna.Framework.Graphics.ModelBone"
  end

  class UndeclaredFixture < CNA::Runtime::ReadOnlyCollection; end

  class WrongElementFixture < CNA::Runtime::ReadOnlyCollection
    projects_elements "Microsoft.Xna.Framework.Graphics.ModelMesh"
  end

  class ArrayFixture < ::Array; end
  class ObjectFixture; end

  def contracts(ruby_name, base:)
    type = {
      "name" => "Microsoft.Xna.Framework.Graphics.FixtureCollection", "rubyName" => ruby_name,
      "kind" => "class", "flags" => false, "baseType" => base, "interfaces" => [],
      "directInterfaces" => [], "genericParameters" => [], "members" => []
    }
    [{"types" => [Marshal.load(Marshal.dump(type))]}, {"types" => [Marshal.load(Marshal.dump(type))]}]
  end

  def diagnostics(ruby_name, base: "#{CLR}[Microsoft.Xna.Framework.Graphics.ModelBone]")
    reference, target = contracts(ruby_name, base: base)
    CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify.counts
  end

  def test_a_correct_bcl_generic_base_is_accepted
    counts = diagnostics("ReadOnlyCollectionTest::CorrectFixture")
    assert_equal 0, counts.fetch("BASE_MAPPING_MISMATCH")
    assert_equal 0, counts.fetch("GENERIC_MAPPING_MISMATCH")
    assert_equal ["Microsoft.Xna.Framework.Graphics.ModelBone"], CorrectFixture.clr_element_types
  end

  def test_mutation_array_substitution_for_the_bcl_base
    assert_operator diagnostics("ReadOnlyCollectionTest::ArrayFixture").fetch("BASE_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_object_fallback_for_the_bcl_base
    assert_operator diagnostics("ReadOnlyCollectionTest::ObjectFixture").fetch("BASE_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_the_support_class_itself_without_element_metadata
    counts = diagnostics("ReadOnlyCollectionTest::UndeclaredFixture")
    assert_equal 0, counts.fetch("BASE_MAPPING_MISMATCH"), "the Ruby base is right"
    assert_operator counts.fetch("GENERIC_MAPPING_MISMATCH"), :>, 0, "but the element projection is missing"
    assert_nil UndeclaredFixture.clr_element_types
  end

  def test_mutation_the_wrong_generic_element_projection
    assert_operator diagnostics("ReadOnlyCollectionTest::WrongElementFixture").fetch("GENERIC_MAPPING_MISMATCH"), :>, 0
  end

  # The projection lives in the CNA runtime, and no ::System namespace is invented for it. A target
  # naming one does not resolve at all, which is the strongest form the check can take.
  def test_mutation_a_fabricated_system_namespace_cannot_resolve
    refute Object.const_defined?(:System, false)
    assert_raises(NameError) do
      "System::Collections::ObjectModel::ReadOnlyCollection"
        .split("::").reduce(Object) { |scope, part| scope.const_get(part, false) }
    end
    assert_equal "CNA::Runtime::ReadOnlyCollection", R.name
    assert_equal CNA::Runtime, R.module_parent if R.respond_to?(:module_parent)
    B::TYPES.each_value { |path| refute path.start_with?("System::"), path }
  end

  # ----------------------------------------------------------------------- the frontier effect

  # The projection unblocks no XNA type on its own, and saying so is the point: the four types that
  # named it each carry another blocker the previous session had not separated out.
  def test_the_frontier_records_exactly_what_the_projection_moved
    by_name = FRONTIER.fetch("dependencyCompleteCandidates").to_h { |entry| [entry.fetch("name"), entry] }

    adapter = by_name.fetch("Microsoft.Xna.Framework.Graphics.GraphicsAdapter")
    assert_equal ["NATIVE_RUNTIME"], adapter.fetch("blockers")
    assert_empty adapter.fetch("unmappedBclTypes")

    # VisualizationData dropped to RUNTIME_DATA alone here and left the frontier entirely in
    # Foundation 51, once that deferral was measured as being about the filler rather than the type.
    refute(by_name.key?("Microsoft.Xna.Framework.Media.VisualizationData"))

    # These two keep a BCL blocker, and it is no longer this one.
    microphone = by_name.fetch("Microsoft.Xna.Framework.Audio.Microphone")
    assert_equal ["System.Byte[]"], microphone.fetch("unmappedBclTypes")
    font = by_name.fetch("Microsoft.Xna.Framework.Graphics.SpriteFont")
    assert_equal ["System.Char", "System.Nullable`1[System.Char]", "System.Text.StringBuilder"],
                 font.fetch("unmappedBclTypes")

    FRONTIER.fetch("dependencyCompleteCandidates").each do |entry|
      assert(entry.fetch("unmappedBclTypes").none? { |identity| identity.include?("ReadOnlyCollection") },
             entry.fetch("name"))
    end
    assert_includes FRONTIER.fetch("mappedBclTypes"), CLR
    # No candidate became consumable *because of this projection*: neither of the two types whose
    # BCL blocker it cleared is consumable now, and the one candidate that is became so in
    # Foundation 31 for an unrelated reason.
    consumable = FRONTIER.fetch("consumableCandidates").map { |entry| entry.fetch("name") }
    refute_includes consumable, "Microsoft.Xna.Framework.Graphics.GraphicsAdapter"
    refute_includes consumable, "Microsoft.Xna.Framework.Media.VisualizationData"
  end

  # A constructed form over a BCL-only type argument is no longer opaque now that the definition is
  # projected — the blind spot Foundation 26 closed, seen from the other side.
  def test_a_constructed_form_reduces_to_the_definition_and_its_arguments
    assert_includes FRONTIER.fetch("mappedBclTypes"), "System.Single"
    refute_includes FRONTIER.fetch("mappedBclTypes"), "System.Char"
    # Single is mapped, so ReadOnlyCollection`1[System.Single] is fully mapped; Char is not, so the
    # SpriteFont form still reports the argument rather than the whole constructed string.
    assert_includes FRONTIER.fetch("dependencyCompleteCandidates")
                            .find { |entry| entry.fetch("name").end_with?("SpriteFont") }
                            .fetch("unmappedBclTypes"), "System.Char"
  end

  # No XNA type was completed *by this projection*. The four types that name ReadOnlyCollection`1
  # are all still missing, and no completed type inherits from the support class, so the
  # inheritance rule is proved by verifier fixtures rather than by a shipped type.
  def test_no_xna_type_became_complete_because_of_this_projection
    %w[
      Microsoft.Xna.Framework.Graphics.GraphicsAdapter
      Microsoft.Xna.Framework.Graphics.SpriteFont
      Microsoft.Xna.Framework.Audio.Microphone
      Microsoft.Xna.Framework.Graphics.ModelBoneCollection
      Microsoft.Xna.Framework.Graphics.ModelEffectCollection
      Microsoft.Xna.Framework.Graphics.ModelMeshCollection
      Microsoft.Xna.Framework.Graphics.ModelMeshPartCollection
    ].each { |name| assert_includes STRICT.fetch("missingTypeNames"), name }

    signatures = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
    inheriting = signatures.fetch("types").select do |entry|
      entry["baseType"].to_s.start_with?(CLR)
    end
    assert_empty inheriting
    assert_equal 0, STRICT.fetch("GENERIC_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("BASE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("LANGUAGE_MAPPING_MISMATCH")
  end
end
