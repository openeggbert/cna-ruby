# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 35 — `Microsoft.Xna.Framework.GameComponentCollection`.
#
# The first shipped XNA type whose CLR base is a projected BCL generic, so it is where the
# Foundation 29 inheritance rule stops being proved by verifier fixtures and starts being proved by
# a real type: it inherits from `CNA::Runtime::Collection` and the whole `Collection<T>` public
# surface arrives by inheritance, rather than being flattened into unrelated methods.
#
# Every behavioural claim is derived from the pinned Microsoft.Xna.Framework.Game.dll IL
# (SHA-256 b5dffdd8…) and the admitted mscorlib, never from another binding's summary. The three
# orderings that matter are all measured rather than assumed:
#
#   InsertItem  duplicate check -> mutation -> event
#   RemoveItem  read -> mutation -> event
#   ClearItems  *all* events -> mutation
class GameComponentCollectionTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  INVENTORY = JSON.parse(ROOT.join("docs", "generated", "bcl-inventory.json").read)

  F = Microsoft::Xna::Framework
  NAME = "Microsoft.Xna.Framework.GameComponentCollection"
  CLR_BASE = "System.Collections.ObjectModel.Collection`1"

  # A minimal component: the IGameComponent contract and nothing else, so nothing here depends on
  # GameComponent, which is a later milestone.
  class Component
    include Microsoft::Xna::Framework::IGameComponent

    attr_reader :label

    def initialize(label = nil)
      @label = label
    end

    def Initialize = nil
  end

  # Equality that is not identity, so the duplicate rule can be shown to use `IndexOf` rather than
  # object identity — which is what `List<T>.IndexOf`'s EqualityComparer<T>.Default does for a type
  # that overrides Equals.
  class EqualComponent < Component
    def ==(other) = other.is_a?(EqualComponent) && other.label == label
    alias eql? ==
    def hash = label.hash
  end

  def reference_type = REFERENCE.fetch("types").find { |type| type.fetch("name") == NAME }

  def target_type = SIGNATURES.fetch("types").find { |type| type.fetch("name") == NAME }

  def collection = F::GameComponentCollection.new

  def recorder(collection)
    log = []
    collection.ComponentAdded.add { |sender, args| log << [:added, sender.equal?(collection), args, collection.Count] }
    collection.ComponentRemoved.add { |sender, args| log << [:removed, sender.equal?(collection), args, collection.Count] }
    log
  end

  # ------------------------------------------------------------------ the CLR base relationship

  def test_the_clr_base_is_the_projected_bcl_generic_and_ruby_really_inherits_from_it
    assert_equal "#{CLR_BASE}[Microsoft.Xna.Framework.IGameComponent]", reference_type.fetch("baseType")
    assert_equal CNA::Runtime::Collection, F::GameComponentCollection.superclass
    assert_operator F::GameComponentCollection, :<, CNA::Runtime::Collection
    refute_operator F::GameComponentCollection, :<, ::Array
    refute_operator F::GameComponentCollection, :<, CNA::Runtime::ReadOnlyCollection

    assert_equal ["Microsoft.Xna.Framework.IGameComponent"], F::GameComponentCollection.clr_element_types
    assert_equal 0, STRICT.fetch("BASE_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("GENERIC_MAPPING_MISMATCH")

    # Foundation 29 could only prove the rule with fixtures because no shipped type inherited from
    # a BCL support class. One now does.
    inheriting = SIGNATURES.fetch("types").select { |type| type["baseType"].to_s.start_with?(CLR_BASE) }
    assert_equal [NAME], inheriting.map { |type| type.fetch("name") }
  end

  # The whole Collection<T> public surface arrives by inheritance. The type itself declares no
  # public member at all beyond the two event readers.
  def test_the_inherited_public_surface_is_present_and_not_redeclared
    CNA::Runtime::Collection::CLR_SURFACE.each do |identity|
      assert F::GameComponentCollection.public_method_defined?(identity), identity
      assert_equal CNA::Runtime::Collection,
                   F::GameComponentCollection.instance_method(identity).owner, identity
    end

    direct = F::GameComponentCollection.public_instance_methods(false)
    assert_equal %i[ComponentAdded ComponentRemoved].sort, direct.sort
    assert_equal CNA::Runtime::Collection::CLR_PROTECTED_SURFACE.sort - [:Items],
                 F::GameComponentCollection.protected_instance_methods(false).sort
  end

  def test_the_selected_surface_is_the_four_hooks_two_events_and_one_constructor
    kinds = reference_type.fetch("members").group_by { |member| member.fetch("kind") }
    assert_equal 1, kinds.fetch("constructor").length
    assert_equal %w[InsertItem RemoveItem SetItem ClearItems].sort,
                 kinds.fetch("method").map { |member| member.fetch("name") }.sort
    kinds.fetch("method").each { |member| assert_equal "protected", member.fetch("access") }
    assert_equal %w[ComponentAdded ComponentRemoved].sort,
                 kinds.fetch("event").map { |member| member.fetch("name") }.sort
    assert reference_type.fetch("sealed")

    assert_includes STRICT.fetch("completeTypeNames"), NAME
    refute_includes STRICT.fetch("missingTypeNames"), NAME
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)
  end

  # ------------------------------------------------------------------- the inherited surface works

  def test_every_inherited_read_answers_over_the_components
    first = Component.new(:a)
    second = Component.new(:b)
    subject = collection
    subject.Add(first)
    subject.Add(second)

    assert_equal 2, subject.Count
    assert_same first, subject[0]
    assert_same second, subject[1]
    assert subject.Contains(first)
    refute subject.Contains(Component.new(:c))
    assert_equal 1, subject.IndexOf(second)
    assert_equal(-1, subject.IndexOf(Component.new(:c)))
    assert_equal [first, second], subject.GetEnumerator.to_a
    assert_equal [first, second], subject.to_a

    destination = Array.new(3)
    subject.CopyTo(destination, 1)
    assert_equal [nil, first, second], destination
  end

  def test_every_inherited_mutation_works_and_keeps_the_collections_order
    a, b, c = Component.new(:a), Component.new(:b), Component.new(:c)
    subject = collection
    subject.Add(a)
    subject.Insert(0, b)
    assert_equal [b, a], subject.to_a

    subject.Insert(2, c)
    assert_equal [b, a, c], subject.to_a
    assert subject.Remove(a)
    assert_equal [b, c], subject.to_a
    refute subject.Remove(a)
    subject.RemoveAt(0)
    assert_equal [c], subject.to_a
    subject.Clear
    assert_equal 0, subject.Count
  end

  # The base bound-checks before reaching the hook, so these are the base's errors, not the
  # collection's, and they arrive with the base's spelling.
  def test_the_inherited_index_validation_still_applies
    subject = collection
    subject.Add(Component.new(:a))

    assert_raises(IndexError) { subject[1] }
    assert_raises(IndexError) { subject[-1] }
    assert_equal "index", assert_raises(RangeError) { subject.RemoveAt(1) }.message
    assert_equal "index", assert_raises(RangeError) { subject.Insert(2, Component.new(:b)) }.message
    subject.Insert(1, Component.new(:b))
    assert_equal 2, subject.Count
  end

  # ------------------------------------------------------------------------------- InsertItem

  def test_a_duplicate_component_is_refused_before_the_insertion_and_before_the_event
    subject = collection
    component = Component.new(:a)
    subject.Add(component)
    log = recorder(subject)

    assert_raises(ArgumentError) { subject.Add(component) }
    assert_equal 1, subject.Count, "the refusal comes before the mutation"
    assert_empty log, "and before the event"

    assert_raises(ArgumentError) { subject.Insert(0, component) }
    assert_equal 1, subject.Count
  end

  # The check is `IndexOf(item) != -1`, and IndexOf is element equality: a component that compares
  # equal to one already present is a duplicate even though it is a different object.
  def test_the_duplicate_rule_is_equality_not_identity
    subject = collection
    subject.Add(EqualComponent.new(:same))
    other = EqualComponent.new(:same)
    refute_same subject[0], other
    assert_equal subject[0], other
    assert_raises(ArgumentError) { subject.Add(other) }

    subject.Add(EqualComponent.new(:different))
    assert_equal 2, subject.Count
  end

  # The CLR message is the localized resource CannotAddSameComponentMultipleTimes and names no
  # parameter, so — like GameServiceContainer's assignability failure — none is reproduced.
  def test_the_refusal_carries_no_reproduced_framework_message
    subject = collection
    component = Component.new(:a)
    subject.Add(component)
    error = assert_raises(ArgumentError) { subject.Add(component) }
    refute_includes error.message, "Component"
    refute_includes error.message, "multiple"
  end

  def test_the_added_event_fires_after_the_mutation_with_the_collection_as_sender
    subject = collection
    log = recorder(subject)
    component = Component.new(:a)
    subject.Add(component)

    assert_equal 1, log.length
    kind, from_collection, args, count_at_dispatch = log.first
    assert_equal :added, kind
    assert from_collection, "sender is the collection"
    assert_instance_of F::GameComponentCollectionEventArgs, args
    assert_same component, args.GameComponent
    assert_equal 1, count_at_dispatch, "the component is already in the collection when it fires"
  end

  # Every notification constructs a fresh GameComponentCollectionEventArgs, so no two share one.
  def test_each_notification_carries_its_own_event_args_object
    subject = collection
    seen = []
    subject.ComponentAdded.add { |_sender, args| seen << args }
    subject.ComponentRemoved.add { |_sender, args| seen << args }
    component = Component.new(:a)
    subject.Add(component)
    subject.Remove(component)

    assert_equal 2, seen.length
    refute_same seen[0], seen[1]
    assert_same component, seen[0].GameComponent
    assert_same component, seen[1].GameComponent
  end

  # -------------------------------------------------------------------------------- RemoveItem

  def test_the_removed_event_fires_after_the_mutation_and_carries_the_component_that_was_there
    subject = collection
    a, b = Component.new(:a), Component.new(:b)
    subject.Add(a)
    subject.Add(b)
    log = recorder(subject)

    assert subject.Remove(a)
    assert_equal 1, log.length
    kind, from_collection, args, count_at_dispatch = log.first
    assert_equal :removed, kind
    assert from_collection
    assert_same a, args.GameComponent
    assert_equal 1, count_at_dispatch, "the component is already gone when it fires"

    subject.RemoveAt(0)
    assert_equal 2, log.length
    assert_same b, log.last[2].GameComponent
    assert_equal 0, log.last[3]
  end

  def test_removing_an_absent_component_reaches_no_hook_and_raises_no_event
    subject = collection
    subject.Add(Component.new(:a))
    log = recorder(subject)
    refute subject.Remove(Component.new(:b))
    assert_empty log
    assert_equal 1, subject.Count
  end

  # ----------------------------------------------------------------------------------- SetItem

  def test_setting_an_item_is_refused_unconditionally
    subject = collection
    subject.Add(Component.new(:a))
    assert_raises(CNA::Runtime::NotSupportedError) { subject[0] = Component.new(:b) }
    assert_equal :a, subject[0].label

    # Even a component already present, and even nil.
    assert_raises(CNA::Runtime::NotSupportedError) { subject[0] = subject[0] }
    assert_raises(CNA::Runtime::NotSupportedError) { subject[0] = nil }
  end

  # The refusal is reached *through* Collection<T>::set_Item, which validates the index first, so
  # an out-of-range index answers the base's RangeError and the hook is never entered.
  def test_the_base_range_check_runs_before_the_unconditional_refusal
    subject = collection
    subject.Add(Component.new(:a))
    assert_equal "index", assert_raises(RangeError) { subject[1] = Component.new(:b) }.message
    assert_equal "index", assert_raises(RangeError) { subject[-1] = Component.new(:b) }.message
    assert_raises(CNA::Runtime::NotSupportedError) { subject[0] = Component.new(:b) }
  end

  def test_the_refusal_carries_no_reproduced_framework_message_either
    subject = collection
    subject.Add(Component.new(:a))
    error = assert_raises(CNA::Runtime::NotSupportedError) { subject[0] = Component.new(:b) }
    refute_includes error.message, "GameComponentCollection"
    refute_includes error.message, "Items"
  end

  # --------------------------------------------------------------------------------- ClearItems

  # The opposite ordering from the other two hooks, and the reason a summary from another binding
  # could not have been trusted: all events fire before anything is removed.
  def test_clear_raises_every_event_before_it_mutates_anything
    subject = collection
    components = [Component.new(:a), Component.new(:b), Component.new(:c)]
    components.each { |component| subject.Add(component) }
    log = recorder(subject)

    subject.Clear

    assert_equal 3, log.length
    assert_equal [:removed, :removed, :removed], log.map(&:first)
    assert_equal components, log.map { |entry| entry[2].GameComponent },
                 "announced in index order"
    assert_equal [3, 3, 3], log.map(&:last),
                 "Count is still 3 for every one of them: no mutation happens until they are done"
    assert_equal 0, subject.Count
  end

  # `for (i = 0; i < base.Count; i++)` re-reads Count, so a handler that adds during Clear extends
  # the loop and the new component is announced as removed too — before being cleared with the rest.
  def test_clear_re_reads_count_on_every_iteration
    subject = collection
    subject.Add(Component.new(:a))
    late = Component.new(:late)
    announced = []
    subject.ComponentRemoved.add do |_sender, args|
      announced << args.GameComponent
      subject.Add(late) if args.GameComponent.label == :a
    end

    subject.Clear
    assert_equal [:a, :late], announced.map(&:label)
    assert_equal 0, subject.Count
  end

  def test_clearing_an_empty_collection_raises_nothing
    subject = collection
    log = recorder(subject)
    subject.Clear
    assert_empty log
    assert_equal 0, subject.Count
  end

  # ------------------------------------------------------------------------- the null component

  # Collection<IGameComponent> admits null and so does the hook: the IL's null check guards the
  # *event*, not the insertion.
  def test_a_null_component_is_inserted_silently
    subject = collection
    log = recorder(subject)
    subject.Add(nil)

    assert_equal 1, subject.Count
    assert_nil subject[0]
    assert_empty log, "no event: the null check guards the notification, not the mutation"
  end

  # And a second null is a duplicate, because IndexOf(null) finds the first one.
  def test_a_second_null_component_is_a_duplicate
    subject = collection
    subject.Add(nil)
    assert_raises(ArgumentError) { subject.Add(nil) }
    assert_equal 1, subject.Count
  end

  def test_removing_a_null_component_is_silent_too
    subject = collection
    subject.Add(nil)
    log = recorder(subject)
    subject.RemoveAt(0)
    assert_equal 0, subject.Count
    assert_empty log
  end

  # ClearItems has no null check, unlike the other two hooks, so a null element *is* announced —
  # with a GameComponentCollectionEventArgs carrying null.
  def test_clear_announces_a_null_component_where_remove_does_not
    subject = collection
    subject.Add(nil)
    subject.Add(Component.new(:a))
    seen = []
    subject.ComponentRemoved.add { |_sender, args| seen << args.GameComponent }

    subject.Clear
    assert_equal 2, seen.length
    assert_nil seen[0]
    assert_equal :a, seen[1].label
  end

  # ---------------------------------------------------------- the element type is a real constraint

  def test_a_non_component_is_refused_at_every_insertion_point
    subject = collection
    assert_raises(TypeError) { subject.Add("not a component") }
    assert_raises(TypeError) { subject.Insert(0, 42) }
    assert_equal 0, subject.Count
    assert_equal ["Microsoft.Xna.Framework.IGameComponent"], F::GameComponentCollection.clr_element_types
  end

  # ------------------------------------------------------------------ the event projection rules

  def test_the_events_use_the_established_projection_and_add_no_primitive
    assert_equal %i[ComponentAdded ComponentRemoved], F::GameComponentCollection.xna_event_identities
    subject = collection
    assert_instance_of CNA::Runtime::Event, subject.ComponentAdded
    assert_instance_of CNA::Runtime::Event, subject.ComponentRemoved
    assert_same subject.ComponentAdded, subject.ComponentAdded
    refute_same subject.ComponentAdded, subject.ComponentRemoved
    refute_same subject.ComponentAdded, collection.ComponentAdded

    %i[add_ComponentAdded remove_ComponentAdded ComponentAdded=
       add_ComponentRemoved remove_ComponentRemoved ComponentRemoved=].each do |leaked|
      refute F::GameComponentCollection.method_defined?(leaked), leaked
      refute F::GameComponentCollection.private_method_defined?(leaked), leaked
    end

    # Raising stays internal: no consumer-facing helper appears on the collection either.
    %i[dispatch raise emit fire trigger invoke OnComponentAdded OnComponentRemoved].each do |leaked|
      refute F::GameComponentCollection.public_method_defined?(leaked), leaked
      refute F::GameComponentCollection.protected_method_defined?(leaked), leaked
    end
    assert_equal 6, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal 3, STRICT.fetch("EVENT_OWNER_TYPES")
    assert_equal 0, STRICT.fetch("EVENT_MAPPING_MISMATCH")
  end

  def test_registration_order_snapshot_and_exception_semantics_are_the_qualified_ones
    subject = collection
    order = []
    first = subject.ComponentAdded.add { |_s, _a| order << :first }
    subject.ComponentAdded.add { |_s, _a| order << :second }
    subject.Add(Component.new(:a))
    assert_equal %i[first second], order

    subject.ComponentAdded.remove(first)
    order.clear
    subject.Add(Component.new(:b))
    assert_equal [:second], order

    # A handler that subscribes during dispatch does not disturb the invocation already in flight.
    late = []
    subject.ComponentAdded.add { |_s, _a| subject.ComponentAdded.add { |_s2, _a2| late << :late } }
    subject.Add(Component.new(:c))
    assert_empty late
    subject.Add(Component.new(:d))
    refute_empty late
  end

  # Exceptions are never swallowed, and the mutation has already happened by the time an added
  # handler can raise — which is exactly what the mutation-before-event ordering means.
  def test_a_raising_handler_propagates_and_leaves_the_mutation_done
    subject = collection
    subject.ComponentAdded.add { |_s, _a| raise "handler" }
    component = Component.new(:a)
    assert_equal "handler", assert_raises(RuntimeError) { subject.Add(component) }.message
    assert_equal 1, subject.Count
    assert_same component, subject[0]

    removing = collection
    removing.Add(component)
    removing.ComponentRemoved.add { |_s, _a| raise "handler" }
    assert_raises(RuntimeError) { removing.Remove(component) }
    assert_equal 0, removing.Count, "removed before the handler ran"
  end

  # Clear is the opposite: a handler raising during the announcement phase stops the whole Clear
  # before anything is removed.
  def test_a_raising_handler_during_clear_leaves_the_collection_untouched
    subject = collection
    subject.Add(Component.new(:a))
    subject.Add(Component.new(:b))
    subject.ComponentRemoved.add { |_s, _a| raise "handler" }
    assert_raises(RuntimeError) { subject.Clear }
    assert_equal 2, subject.Count, "no mutation had happened yet"
  end

  # --------------------------------------------------------------------------- negative controls

  def contracts(ruby_name)
    type = Marshal.load(Marshal.dump(target_type))
    type["rubyName"] = ruby_name
    [{"types" => [Marshal.load(Marshal.dump(reference_type))]}, {"types" => [type]}]
  end

  def diagnostics(ruby_name)
    reference, target = contracts(ruby_name)
    CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify.counts
  end

  class ArrayCollection < ::Array
    def ComponentAdded = CNA::Runtime::Event.new
    def ComponentRemoved = CNA::Runtime::Event.new
  end

  class UndeclaredElements < CNA::Runtime::Collection; end

  class WrongElements < CNA::Runtime::Collection
    projects_elements "Microsoft.Xna.Framework.GameComponent"
  end

  # A single-type fixture necessarily reports the rest of the namespace as an internal type leak,
  # so the shipped type is asserted against every category that is about the type itself.
  MEASURED = %w[MISSING_TYPE MISSING_MEMBER UNEXPECTED_MEMBER TYPE_KIND_MISMATCH
                BASE_MAPPING_MISMATCH GENERIC_MAPPING_MISMATCH EVENT_MAPPING_MISMATCH
                METHOD_SIGNATURE_MAPPING_MISMATCH PARAMETER_MAPPING_MISMATCH
                RETURN_MAPPING_MISMATCH PROPERTY_MAPPING_MISMATCH
                RAW_HANDLE_LEAK PUBLIC_NATIVE_FFI_LEAK].freeze

  def test_the_shipped_type_is_accepted
    counts = diagnostics("Microsoft::Xna::Framework::GameComponentCollection")
    MEASURED.each { |category| assert_equal 0, counts.fetch(category), category }
  end

  def test_mutation_inheriting_array_instead_of_the_bcl_base
    assert_operator diagnostics("GameComponentCollectionTest::ArrayCollection")
                      .fetch("BASE_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_the_support_class_without_element_metadata
    assert_operator diagnostics("GameComponentCollectionTest::UndeclaredElements")
                      .fetch("GENERIC_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_the_wrong_element_projection
    assert_operator diagnostics("GameComponentCollectionTest::WrongElements")
                      .fetch("GENERIC_MAPPING_MISMATCH"), :>, 0
  end

  def test_mutation_a_mutating_member_that_bypasses_the_hooks_is_an_unexpected_member
    F::GameComponentCollection.class_eval { def <<(item) = nil }
    assert_operator diagnostics("Microsoft::Xna::Framework::GameComponentCollection")
                      .fetch("UNEXPECTED_MEMBER"), :>, 0
  ensure
    F::GameComponentCollection.__send__(:remove_method, :<<)
  end

  def test_mutation_a_dropped_event_and_an_invented_one_are_detected
    reference, target = contracts("Microsoft::Xna::Framework::GameComponentCollection")
    target.fetch("types").first.fetch("members").reject! { |member| member["name"] == "ComponentAdded" }
    counts = CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify.counts
    assert_operator counts.fetch("EVENT_MAPPING_MISMATCH"), :>, 0

    reference, target = contracts("Microsoft::Xna::Framework::GameComponentCollection")
    invented = Marshal.load(Marshal.dump(target.fetch("types").first.fetch("members")
                                               .find { |member| member["kind"] == "event" }))
    invented["name"] = "ComponentChanged"
    target.fetch("types").first.fetch("members") << invented
    counts = CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify.counts
    assert_operator counts.fetch("MISSING_MEMBER") + counts.fetch("EVENT_MAPPING_MISMATCH"), :>, 0
  end

  # --------------------------------------------------------------------------- the scoreboard

  def test_the_milestone_completed_exactly_one_type
    assert_equal 140, STRICT.fetch("TARGET_TYPES")
    assert_equal 134, STRICT.fetch("COMPLETE_TYPES")
    assert_equal 117, STRICT.fetch("MISSING_TYPES")
    assert_equal 6, STRICT.fetch("PARTIAL_TYPES")
    assert_equal 0, STRICT.fetch("ALLOWLIST_ENTRIES")
    assert_equal 0, STRICT.fetch("UNMEASURED_STRUCTURAL_CATEGORY")
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
    assert_equal 0, STRICT.fetch("INTERNAL_TYPE_LEAK")
    assert_equal 0, STRICT.fetch("RAW_HANDLE_LEAK")
    assert_equal 0, STRICT.fetch("PUBLIC_NATIVE_FFI_LEAK")
  end

  # The event args type it uses is the one Foundation 24 already completed, unchanged.
  def test_the_event_args_type_was_reused_rather_than_altered
    args_name = "Microsoft.Xna.Framework.GameComponentCollectionEventArgs"
    assert_includes STRICT.fetch("completeTypeNames"), args_name
    args = REFERENCE.fetch("types").find { |type| type.fetch("name") == args_name }
    assert_equal "System.EventArgs", args.fetch("baseType")
    assert_equal CNA::Runtime::EventArgs, F::GameComponentCollectionEventArgs.superclass
    assert_equal %w[GameComponent], args.fetch("members")
                                        .select { |member| member.fetch("kind") == "property" }
                                        .map { |member| member.fetch("name") }
  end
end
