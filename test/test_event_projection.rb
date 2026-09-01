# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"
require_relative "../tools/api_compat/verifier"

# Foundation 20 — the general Ruby event projection.
#
#   A CLR public event  T.EventName : System.EventHandler`1[TArgs]
#   projects to exactly one public Ruby event reader  object.EventName
#   whose value is the generic CNA::Runtime::Event subscription primitive.
#
#     handler = object.EventName.add { |sender, args| ... }
#     object.EventName.remove(handler)
#
# Never an add_EventName/remove_EventName pair, never a writer, never a Proc, Array or callback
# property. Raising stays internal to the declaring implementation, so no consumer-facing emit,
# fire, trigger or call helper exists. This file pins the runtime semantics and every mutation the
# API verifier must reject.
class EventProjectionTest < Minitest::Test
  E = CNA::Runtime::Event
  F = Microsoft::Xna::Framework

  ROOT = Pathname(__dir__).join("..").expand_path
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)

  # A concrete owner, which no selected XNA type is yet: the four selected event identities all sit
  # on abstract interfaces. It exists so the verifier's concrete-owner rules are exercised too.
  class ConcreteFixture
    extend CNA::Runtime::EventOwner

    xna_event :Changed

    def raise_changed(args) = self.Changed.__send__(:dispatch, self, args)
  end

  # ---------------------------------------------------------------- runtime primitive semantics

  def test_the_subscription_surface_is_exactly_add_and_remove
    assert_equal %i[add remove], E.public_instance_methods(false).sort
    assert_empty E.protected_instance_methods(false)
    assert E.private_method_defined?(:dispatch)
    %i[<< >> subscribe unsubscribe clear fire trigger emit invoke notify broadcast publish
       raise_event handlers count length size each to_a].each do |absent|
      refute E.public_method_defined?(absent), "CNA::Runtime::Event##{absent}"
    end
    refute E.respond_to?(:dispatch)
  end

  def test_add_accepts_a_block_or_a_callable_and_returns_a_removal_token
    event = E.new
    seen = []
    block_handler = event.add { |sender, args| seen << [:block, sender, args] }
    assert_kind_of Proc, block_handler

    lambda_handler = ->(sender, args) { seen << [:lambda, sender, args] }
    assert_same lambda_handler, event.add(lambda_handler)

    callable = Class.new { def call(sender, args) = nil }.new
    assert_same callable, event.add(callable)

    event.__send__(:dispatch, :sender, CNA::Runtime::EventArgs::Empty)
    assert_equal %i[block lambda], seen.map(&:first)
    assert_equal [:sender, :sender], seen.map { |entry| entry[1] }
    assert_equal [CNA::Runtime::EventArgs::Empty] * 2, seen.map(&:last)
  end

  def test_a_method_object_is_a_handler_and_removes_by_clr_delegate_equality
    target = Class.new do
      attr_reader :calls
      def initialize = @calls = 0
      def on_changed(_sender, _args) = @calls += 1
    end.new
    event = E.new
    event.add(target.method(:on_changed))
    event.__send__(:dispatch, nil, nil)
    assert_equal 1, target.calls

    # A freshly bound Method is a different Ruby object but the same receiver+method pair, which is
    # exactly what Delegate.Remove matches on.
    refute_same target.method(:on_changed), target.method(:on_changed)
    refute_nil event.remove(target.method(:on_changed))
    event.__send__(:dispatch, nil, nil)
    assert_equal 1, target.calls
  end

  def test_invalid_handlers_are_rejected_cleanly
    event = E.new
    assert_raises(ArgumentError) { event.add }
    assert_raises(ArgumentError) { event.add(->(sender, args) {}) { |sender, args| } }
    assert_raises(TypeError) { event.add(42) }
    assert_raises(TypeError) { event.add("not callable") }
    assert_raises(ArgumentError) { event.add(->(only) {}) }
    assert_raises(ArgumentError) { event.add(->(a, b, c) {}) }

    # Nothing invalid may reach the invocation list.
    calls = 0
    event.add { |_sender, _args| calls += 1 }
    event.__send__(:dispatch, nil, nil)
    assert_equal 1, calls

    # A splat lambda, an optional-argument lambda and an ordinary Proc all accept (sender, args).
    [->(*rest) {}, ->(a, b = nil) {}, proc { |a| }].each { |handler| assert_same handler, event.add(handler) }
  end

  def test_invocation_order_is_registration_order
    event = E.new
    order = []
    5.times { |index| event.add { |_sender, _args| order << index } }
    event.__send__(:dispatch, nil, nil)
    assert_equal [0, 1, 2, 3, 4], order
  end

  def test_duplicate_subscriptions_are_permitted_and_remove_takes_the_last_occurrence
    event = E.new
    order = []
    first = ->(_sender, _args) { order << :first }
    second = ->(_sender, _args) { order << :second }
    event.add(first)
    event.add(second)
    event.add(first)
    event.__send__(:dispatch, nil, nil)
    assert_equal %i[first second first], order

    order.clear
    assert_same first, event.remove(first)
    event.__send__(:dispatch, nil, nil)
    assert_equal %i[first second], order
  end

  def test_removing_an_absent_handler_is_harmless
    event = E.new
    assert_nil event.remove(->(_sender, _args) {})
    assert_nil event.remove(nil)
    assert_nil event.remove(:never_subscribed)

    handler = event.add { |_sender, _args| }
    refute_nil event.remove(handler)
    assert_nil event.remove(handler)
  end

  def test_dispatch_uses_a_snapshot_so_mutation_during_dispatch_is_safe
    event = E.new
    seen = []
    late = ->(_sender, _args) { seen << :late }
    removed = ->(_sender, _args) { seen << :removed }
    event.add { |_sender, _args| seen << :first }
    event.add do |_sender, _args|
      seen << :second
      event.add(late)
      event.remove(removed)
    end
    event.add(removed)

    event.__send__(:dispatch, nil, nil)
    assert_equal %i[first second removed], seen

    seen.clear
    event.__send__(:dispatch, nil, nil)
    assert_equal %i[first second late], seen
  end

  def test_the_first_exception_propagates_and_later_handlers_are_not_invoked
    event = E.new
    seen = []
    event.add { |_sender, _args| seen << :before }
    event.add { |_sender, _args| raise ArgumentError, "handler failed" }
    event.add { |_sender, _args| seen << :after }

    error = assert_raises(ArgumentError) { event.__send__(:dispatch, nil, nil) }
    assert_equal "handler failed", error.message
    assert_equal [:before], seen

    # The invocation list is untouched, so a later dispatch behaves identically.
    seen.clear
    assert_raises(ArgumentError) { event.__send__(:dispatch, nil, nil) }
    assert_equal [:before], seen
  end

  def test_each_owner_instance_owns_its_own_invocation_list
    first = ConcreteFixture.new
    second = ConcreteFixture.new
    refute_same first.Changed, second.Changed
    assert_same first.Changed, first.Changed

    seen = []
    first.Changed.add { |sender, args| seen << [sender, args] }
    second.raise_changed(CNA::Runtime::EventArgs::Empty)
    assert_empty seen
    first.raise_changed(CNA::Runtime::EventArgs::Empty)
    assert_equal [[first, CNA::Runtime::EventArgs::Empty]], seen
  end

  # ------------------------------------------------------------------------ System.EventArgs

  def test_event_args_projects_only_its_two_public_clr_identities
    args = CNA::Runtime::EventArgs
    assert_instance_of args, args::Empty
    assert args::Empty.frozen?
    assert_same args::Empty, args::Empty
    assert_instance_of args, args.new
    refute_same args::Empty, args.new
    assert_equal [:Empty], args.constants(false)
    assert_empty args.public_instance_methods(false)
    assert_equal Object, args.superclass
  end

  def test_nil_is_never_the_event_args_representation
    fixture = ConcreteFixture.new
    seen = []
    fixture.Changed.add { |_sender, args| seen << args }
    fixture.raise_changed(CNA::Runtime::EventArgs::Empty)
    assert_equal [CNA::Runtime::EventArgs::Empty], seen
    refute_nil seen.first
  end

  # --------------------------------------------------------------- declared identity accounting

  def test_declared_event_identities_are_recorded_and_inherited
    assert_equal %i[Changed], ConcreteFixture.xna_event_identities
    assert_equal %i[EnabledChanged UpdateOrderChanged], F::IUpdateable.xna_event_identities
    assert_equal %i[VisibleChanged DrawOrderChanged], F::IDrawable.xna_event_identities

    derived = Class.new(ConcreteFixture) do
      extend CNA::Runtime::EventOwner
      xna_event :AlsoChanged
    end
    assert_equal %i[Changed AlsoChanged], derived.xna_event_identities

    duplicate = Class.new { extend CNA::Runtime::EventOwner }
    duplicate.xna_event :Once
    assert_raises(ArgumentError) { duplicate.xna_event :Once }
  end

  def test_an_abstract_contract_declares_the_identity_without_owning_an_invocation_list
    %w[IUpdateable IDrawable].each do |short|
      interface = F.const_get(short, false)
      host = Class.new { include(interface) }
      interface.xna_event_identities.each do |identity|
        error = assert_raises(NotImplementedError) { host.new.public_send(identity) }
        assert_equal "#{short}##{identity}", error.message
      end
    end
  end

  # ------------------------------------------------------------------------ verifier mutations

  def concrete_contracts
    type = {
      "name" => "Microsoft.Xna.Framework.Fixture",
      "rubyName" => "EventProjectionTest::ConcreteFixture",
      "kind" => "class", "flags" => false, "baseType" => "System.Object", "interfaces" => [],
      "directInterfaces" => [], "genericParameters" => [], "members" => [
        {"kind" => "event", "name" => "Changed", "static" => false,
         "type" => "System.EventHandler`1[System.EventArgs]", "add" => true, "remove" => true}
      ]
    }
    [{"types" => [Marshal.load(Marshal.dump(type))]}, {"types" => [Marshal.load(Marshal.dump(type))]}]
  end

  def interface_contracts(type_name)
    reference_type = REFERENCE.fetch("types").find { |type| type.fetch("name") == type_name }
    target_type = SIGNATURES.fetch("types").find { |type| type.fetch("name") == type_name }
    [{"types" => [Marshal.load(Marshal.dump(reference_type))]},
     {"types" => [Marshal.load(Marshal.dump(target_type))]}]
  end

  def events_reported(reference, target)
    result = CNAApiCompat::Verifier.new(reference: reference, target: target, runtime: true).verify
    [result.counts.fetch("EVENT_MAPPING_MISMATCH"), result]
  end

  def assert_event_mutation_detected(reference, target, label)
    count, = events_reported(reference, target)
    assert_operator count, :>, 0, label
  end

  # Restores whatever the mutation did, so one failing mutation cannot cascade.
  def with_method(owner, name)
    original = owner.instance_method(name)
    yield
  ensure
    owner.__send__(:remove_method, name) if owner.instance_methods(false).include?(name) ||
                                            owner.private_instance_methods(false).include?(name)
    owner.__send__(:define_method, name, original)
  end

  def test_the_projected_contracts_report_no_event_mismatch
    ["Microsoft.Xna.Framework.IUpdateable", "Microsoft.Xna.Framework.IDrawable"].each do |name|
      count, = events_reported(*interface_contracts(name))
      assert_equal 0, count, name
    end
    count, = events_reported(*concrete_contracts)
    assert_equal 0, count
  end

  def test_mutation_missing_event
    with_method(F::IUpdateable, :EnabledChanged) do
      F::IUpdateable.__send__(:remove_method, :EnabledChanged)
      reference, target = interface_contracts("Microsoft.Xna.Framework.IUpdateable")
      count, result = events_reported(reference, target)
      assert_operator count, :>, 0
      assert_operator result.counts.fetch("MISSING_MEMBER"), :>, 0
      refute_includes result.complete_types, "Microsoft.Xna.Framework.IUpdateable"
    end
  end

  def test_mutation_renamed_event
    reference, target = interface_contracts("Microsoft.Xna.Framework.IUpdateable")
    target.fetch("types").first.fetch("members")
          .find { |member| member["name"] == "EnabledChanged" }["name"] = "EnabledAltered"
    count, result = events_reported(reference, target)
    assert_operator count, :>, 0
    assert_operator result.counts.fetch("MISSING_MEMBER"), :>, 0
    assert_operator result.counts.fetch("UNEXPECTED_MEMBER"), :>, 0
  end

  def test_mutation_event_projected_as_ordinary_mutable_property
    with_method(ConcreteFixture, :Changed) do
      ConcreteFixture.__send__(:remove_method, :Changed)
      ConcreteFixture.class_eval { attr_accessor :Changed }
      begin
        reference, target = concrete_contracts
        count, = events_reported(reference, target)
        assert_operator count, :>, 1, "both the writer and the wrong value must be reported"
      ensure
        ConcreteFixture.__send__(:remove_method, :Changed=)
      end
    end
  end

  def test_mutation_event_projected_as_writer_only
    with_method(ConcreteFixture, :Changed) do
      ConcreteFixture.__send__(:remove_method, :Changed)
      ConcreteFixture.class_eval { attr_writer :Changed }
      begin
        reference, target = concrete_contracts
        count, result = events_reported(reference, target)
        assert_operator count, :>, 0
        assert_operator result.counts.fetch("MISSING_MEMBER"), :>, 0
      ensure
        ConcreteFixture.__send__(:remove_method, :Changed=)
      end
    end
  end

  def test_mutation_wrong_event_support_type
    replacements = {
      "a Proc" => -> { ConcreteFixture.class_eval { def Changed = proc { |sender, args| } } },
      "an Array" => -> { ConcreteFixture.class_eval { def Changed = [] } },
      "nil" => -> { ConcreteFixture.class_eval { def Changed = nil } },
      "a lookalike" => lambda {
        lookalike = Class.new { def add(callable = nil, &block) = nil; def remove(handler) = nil }
        ConcreteFixture.__send__(:define_method, :Changed) { lookalike.new }
      }
    }
    replacements.each do |label, mutate|
      with_method(ConcreteFixture, :Changed) do
        ConcreteFixture.__send__(:remove_method, :Changed)
        mutate.call
        assert_event_mutation_detected(*concrete_contracts, label)
      end
    end
  end

  def test_mutation_duplicate_extra_event_identity
    ConcreteFixture.xna_event :Extra
    begin
      reference, target = concrete_contracts
      count, result = events_reported(reference, target)
      assert_operator count, :>, 0
      assert_operator result.counts.fetch("UNEXPECTED_MEMBER"), :>, 0
    ensure
      ConcreteFixture.__send__(:remove_method, :Extra)
      ConcreteFixture.instance_variable_get(:@xna_event_identities).delete(:Extra)
    end
  end

  def test_mutation_add_eventname_leakage
    ConcreteFixture.class_eval { def add_Changed(handler) = nil }
    begin
      assert_event_mutation_detected(*concrete_contracts, "add_Changed")
    ensure
      ConcreteFixture.__send__(:remove_method, :add_Changed)
    end
  end

  def test_mutation_remove_eventname_leakage
    ConcreteFixture.class_eval { def remove_Changed(handler) = nil }
    begin
      assert_event_mutation_detected(*concrete_contracts, "remove_Changed")
    ensure
      ConcreteFixture.__send__(:remove_method, :remove_Changed)
    end
  end

  def test_mutation_unexpected_public_raise_surface
    %i[emit fire trigger call invoke broadcast notify publish raise_event dispatch].each do |leaked|
      existing = E.private_method_defined?(leaked) ? E.instance_method(leaked) : nil
      E.__send__(:define_method, leaked) { |*| nil }
      begin
        count, result = events_reported(*concrete_contracts)
        assert_operator count, :>, 0, leaked
        assert result.details.fetch("EVENT_MAPPING_MISMATCH").any? { |detail| detail.include?(leaked.to_s) },
               leaked
      ensure
        E.__send__(:remove_method, leaked)
        if existing
          E.__send__(:define_method, leaked, existing)
          E.__send__(:private, leaked)
        end
      end
    end
    # dispatch stays available privately after the public mutation is undone.
    assert E.private_method_defined?(:dispatch)
    assert_equal %i[add remove], E.public_instance_methods(false).sort
  end

  def test_mutation_event_omitted_from_verifier_expectations
    reference, target = concrete_contracts
    target.fetch("types").first["members"] = []
    count, result = events_reported(reference, target)
    assert_operator count, :>, 0, "a runtime event identity nothing selects must be reported"
    assert_operator result.counts.fetch("UNEXPECTED_MEMBER"), :>, 0
  end

  def test_mutation_event_declared_outside_the_generic_primitive
    fixture = Class.new { def Changed = CNA::Runtime::Event.new }
    EventProjectionTest.const_set(:UnregisteredFixture, fixture)
    begin
      reference, target = concrete_contracts
      [reference, target].each { |contract| contract.fetch("types").first["rubyName"] = "EventProjectionTest::UnregisteredFixture" }
      count, result = events_reported(reference, target)
      assert_operator count, :>, 0
      assert result.details.fetch("EVENT_MAPPING_MISMATCH")
                   .any? { |detail| detail.include?("not declared through CNA::Runtime::Event") }
    ensure
      EventProjectionTest.__send__(:remove_const, :UnregisteredFixture)
    end
  end

  # ------------------------------------------------------------------------ measured evidence

  # Foundation 20 established the projection with two abstract owners and four identities;
  # Foundation 35 added the first concrete owner, which is what an event projection is ultimately
  # for; Foundation 40 added a third abstract owner carrying four more. The rule is unchanged and
  # the census grew.
  def test_the_strict_report_measures_the_selected_event_identities
    assert_equal ReviewedScoreboard::EVENT_IDENTITIES, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal ReviewedScoreboard::EVENT_OWNER_TYPES, STRICT.fetch("EVENT_OWNER_TYPES")
    assert_equal "CNA::Runtime::Event", STRICT.fetch("EVENT_SUPPORT_TYPE")
    assert_equal 0, STRICT.fetch("EVENT_MAPPING_MISMATCH")
    assert_equal 0, STRICT.fetch("UNMEASURED_STRUCTURAL_CATEGORY")
    assert_equal %w[
      Microsoft.Xna.Framework.GameComponentCollection::ComponentAdded
      Microsoft.Xna.Framework.GameComponentCollection::ComponentRemoved
      Microsoft.Xna.Framework.GameComponent::EnabledChanged
      Microsoft.Xna.Framework.GameComponent::UpdateOrderChanged
      Microsoft.Xna.Framework.GameComponent::Disposed
      Microsoft.Xna.Framework.IUpdateable::EnabledChanged
      Microsoft.Xna.Framework.IUpdateable::UpdateOrderChanged
      Microsoft.Xna.Framework.IDrawable::VisibleChanged
      Microsoft.Xna.Framework.IDrawable::DrawOrderChanged
      Microsoft.Xna.Framework.Audio.DynamicSoundEffectInstance::BufferNeeded
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceDisposing
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceReset
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceResetting
      Microsoft.Xna.Framework.Graphics.IGraphicsDeviceService::DeviceCreated
      Microsoft.Xna.Framework.Game::Activated
      Microsoft.Xna.Framework.Game::Deactivated
      Microsoft.Xna.Framework.Game::Exiting
      Microsoft.Xna.Framework.Game::Disposed
      Microsoft.Xna.Framework.GameWindow::ScreenDeviceNameChanged
      Microsoft.Xna.Framework.GameWindow::ClientSizeChanged
      Microsoft.Xna.Framework.GameWindow::OrientationChanged
      Microsoft.Xna.Framework.Audio.Microphone::BufferReady
      Microsoft.Xna.Framework.Audio.AudioEngine::Disposing
      Microsoft.Xna.Framework.Audio.WaveBank::Disposing
      Microsoft.Xna.Framework.Audio.SoundBank::Disposing
      Microsoft.Xna.Framework.Audio.Cue::Disposing
    ], STRICT.fetch("eventIdentities")
  end

  def test_event_projection_adds_no_public_xna_surface_beyond_the_readers
    %w[IUpdateable IDrawable].each do |short|
      interface = F.const_get(short, false)
      assert_empty interface.constants(false), short
      assert_empty interface.singleton_methods(false), short
      assert_empty interface.private_instance_methods(false), short
      assert_empty interface.protected_instance_methods(false), short
    end
    refute F.const_defined?(:EventArgs, false)
    refute Object.const_defined?(:System, false), "no fabricated ::System namespace"
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:constants), CNA::Native::Manifest::CONSTANTS.length
  end
end
