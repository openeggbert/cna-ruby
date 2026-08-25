# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require "objspace"
require_relative "../lib/cna"

# Foundation 38 — `Microsoft.Xna.Framework.GameComponent`.
#
# Fourteen identities, pure managed, derived from the pinned Microsoft.Xna.Framework.Game.dll IL
# (SHA-256 b5dffdd8…). It is the first concrete component type this binding ships, so it is where
# the engine Foundation 37 built stops being exercised by fixtures.
#
# Four measured facts a summary would have got wrong:
#
#   * the constructor has **no null check**, so a component with no Game is legal;
#   * both setters suppress a same-value write *before* anything else, and write the field *before*
#     raising, so a handler always observes the new value;
#   * `OnEnabledChanged`/`OnUpdateOrderChanged` declare a `sender` parameter and **ignore it**;
#   * there is **no disposed flag anywhere in the type**, so disposing twice raises `Disposed`
#     twice.
class GameComponentTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  F = Microsoft::Xna::Framework
  NAME = "Microsoft.Xna.Framework.GameComponent"

  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)
  SIGNATURES = JSON.parse(ROOT.join("tools", "api_compat", "signatures.json").read)
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  IL = JSON.parse(ROOT.join("docs", "generated", "xna-il-inventory.json").read)

  def reference_type = REFERENCE.fetch("types").find { |type| type.fetch("name") == NAME }

  def setup
    @game = F::Game.new
    @time = F::GameTime.new
  end

  def teardown
    @game&.Dispose
  rescue StandardError
    nil
  end

  def component(game = @game) = F::GameComponent.new(game)

  # ------------------------------------------------------------------------------ the contract

  def test_the_type_is_complete_and_reaches_no_native_entry_point
    assert_includes STRICT.fetch("completeTypeNames"), NAME
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)
    refute IL.fetch("types").fetch(NAME).fetch("nativeReachable")
    assert_empty IL.fetch("types").fetch(NAME).fetch("nativeReachableMethods")
    assert_equal 39, CNA::Native::Manifest::FUNCTIONS.length
  end

  def test_it_declares_fourteen_identities_over_the_measured_shape
    assert_equal "System.Object", reference_type.fetch("baseType")
    assert_equal F::GameComponent.superclass, Object
    refute reference_type.fetch("sealed")
    assert_equal 14, reference_type.fetch("members").length
  end

  # The two XNA contracts are really included, which is what `Game`'s engine tests with `is_a?`.
  # `System.IDisposable` contributes no inclusion because Foundation 36 collapsed it.
  def test_the_xna_contracts_are_included_and_idisposable_is_not
    assert_equal %w[Microsoft.Xna.Framework.IGameComponent Microsoft.Xna.Framework.IUpdateable
                    System.IDisposable].sort,
                 reference_type.fetch("directInterfaces").sort

    subject = component
    assert_kind_of F::IGameComponent, subject
    assert_kind_of F::IUpdateable, subject
    assert_includes F::GameComponent.ancestors, F::IGameComponent
    assert_includes F::GameComponent.ancestors, F::IUpdateable
    refute Object.const_defined?(:IDisposable, false)
    refute CNA::Runtime.const_defined?(:IDisposable, false)
    refute F.const_defined?(:IDisposable, false)
  end

  # Every member either contract declares is overridden, so no abstract NotImplementedError
  # survives on a concrete component.
  def test_no_abstract_contract_member_survives
    subject = component
    assert_nil subject.Initialize
    assert_nil subject.Update(@time)
    assert_equal true, subject.Enabled
    assert_equal 0, subject.UpdateOrder
    assert_instance_of CNA::Runtime::Event, subject.EnabledChanged
    assert_instance_of CNA::Runtime::Event, subject.UpdateOrderChanged

    %i[Initialize Update Enabled UpdateOrder].each do |identity|
      refute_equal F::IGameComponent, F::GameComponent.instance_method(identity).owner rescue nil
      refute_equal F::IUpdateable, F::GameComponent.instance_method(identity).owner
    end
  end

  # ---------------------------------------------------------------------------- the constructor

  def test_the_constructor_stores_the_game_and_sets_the_measured_defaults
    subject = component
    assert_same @game, subject.Game
    assert_equal true, subject.Enabled, "enabled = true is a field initialiser"
    assert_equal 0, subject.UpdateOrder, "updateOrder gets the CLR default and nothing assigns it"
  end

  # `.ctor` is twenty-one bytes with no branch: a null Game is stored as-is.
  def test_a_component_with_no_game_is_legal
    subject = component(nil)
    assert_nil subject.Game
    assert_equal true, subject.Enabled
    assert_nil subject.Dispose, "Dispose skips the removal when Game is null"
  end

  def test_the_game_property_is_read_only
    member = reference_type.fetch("members").find { |entry| entry.fetch("name") == "Game" }
    assert member.fetch("get")
    refute member.fetch("set")
    refute F::GameComponent.method_defined?(:Game=)
  end

  def test_the_constructor_rejects_something_that_is_not_a_game
    assert_raises(TypeError) { F::GameComponent.new(:not_a_game) }
  end

  # ------------------------------------------------------------------------------ the properties

  def test_setting_enabled_writes_the_field_before_raising_and_the_handler_sees_the_new_value
    subject = component
    seen = []
    subject.EnabledChanged.add { |sender, args| seen << [sender.equal?(subject), subject.Enabled, args] }

    subject.Enabled = false
    assert_equal false, subject.Enabled
    assert_equal 1, seen.length
    from_component, value, args = seen.first
    assert from_component, "the sender is the component"
    assert_equal false, value, "the field is written before the notification"
    assert_same CNA::Runtime::EventArgs::Empty, args
  end

  def test_setting_update_order_writes_the_field_before_raising
    subject = component
    seen = []
    subject.UpdateOrderChanged.add { |sender, args| seen << [sender.equal?(subject), subject.UpdateOrder, args] }

    subject.UpdateOrder = 7
    assert_equal 7, subject.UpdateOrder
    assert_equal [[true, 7, CNA::Runtime::EventArgs::Empty]], seen
  end

  # `if (field == value) return;` is the first branch in both setters.
  def test_a_same_value_write_raises_nothing
    subject = component
    raised = 0
    subject.EnabledChanged.add { |_s, _a| raised += 1 }
    subject.UpdateOrderChanged.add { |_s, _a| raised += 1 }

    subject.Enabled = true
    subject.UpdateOrder = 0
    assert_equal 0, raised

    subject.Enabled = false
    subject.UpdateOrder = 1
    assert_equal 2, raised

    subject.Enabled = false
    subject.UpdateOrder = 1
    assert_equal 2, raised, "still suppressed at the new value"
  end

  def test_update_order_is_an_int32
    subject = component
    assert_raises(TypeError) { subject.UpdateOrder = "3" }
    assert_raises(RangeError) { subject.UpdateOrder = 2**31 }
    subject.UpdateOrder = -5
    assert_equal(-5, subject.UpdateOrder)
  end

  # The Microsoft quirk: both hooks declare a `sender` and load `ldarg.0` — `this` — instead.
  def test_the_protected_hooks_ignore_their_sender_argument
    subject = component
    other = component
    seen = []
    subject.EnabledChanged.add { |sender, _args| seen << sender }
    subject.UpdateOrderChanged.add { |sender, _args| seen << sender }

    subject.__send__(:OnEnabledChanged, other, CNA::Runtime::EventArgs::Empty)
    subject.__send__(:OnUpdateOrderChanged, :nonsense, CNA::Runtime::EventArgs::Empty)

    assert_equal [subject, subject], seen, "the declared sender is never read"
    refute_includes seen, other
  end

  def test_the_two_hooks_are_protected_and_the_events_carry_no_leaked_identity
    %i[OnEnabledChanged OnUpdateOrderChanged Finalize].each do |identity|
      assert F::GameComponent.protected_method_defined?(identity), identity
      refute F::GameComponent.public_method_defined?(identity), identity
    end
    %i[EnabledChanged UpdateOrderChanged Disposed].each do |identity|
      assert F::GameComponent.public_method_defined?(identity), identity
      %W[add_#{identity} remove_#{identity} #{identity}=].each do |leaked|
        refute F::GameComponent.method_defined?(leaked), leaked
        refute F::GameComponent.private_method_defined?(leaked), leaked
      end
    end
    assert_equal %i[EnabledChanged UpdateOrderChanged Disposed], F::GameComponent.xna_event_identities
  end

  # -------------------------------------------------------------------------- Initialize / Update

  def test_both_virtual_hooks_are_bare_rets_and_public
    subject = component
    assert F::GameComponent.public_method_defined?(:Initialize)
    assert F::GameComponent.public_method_defined?(:Update)
    assert_nil subject.Initialize
    assert_nil subject.Update(@time)
    assert_raises(TypeError) { subject.Update(nil) }
  end

  class Counting < Microsoft::Xna::Framework::GameComponent
    attr_reader :log

    def initialize(game)
      super
      @log = []
    end

    def Initialize
      @log << :initialize
      super
    end

    def Update(game_time)
      @log << :update
      super
    end
  end

  def test_a_subclass_overrides_with_ordinary_ruby_inheritance
    subject = Counting.new(@game)
    subject.Initialize
    subject.Update(@time)
    assert_equal %i[initialize update], subject.log
    assert_kind_of F::GameComponent, subject
    assert_kind_of F::IUpdateable, subject
  end

  # ---------------------------------------------------------------------------------- Dispose

  # The removal happens first, under the lock, so a Disposed handler sees the component already out
  # of the collection.
  def test_dispose_removes_the_component_before_raising_disposed
    subject = component
    @game.Components.Add(subject)
    seen = []
    subject.Disposed.add { |sender, args| seen << [sender.equal?(subject), @game.Components.Count, args] }

    assert_nil subject.Dispose
    assert_equal 0, @game.Components.Count
    assert_equal [[true, 0, CNA::Runtime::EventArgs::Empty]], seen
  end

  # The removal goes through GameComponentCollection.RemoveItem, so the collection's own
  # ComponentRemoved fires too — and before Disposed, because it fires inside the Remove call.
  def test_the_collections_removed_event_fires_before_disposed
    subject = component
    @game.Components.Add(subject)
    order = []
    @game.Components.ComponentRemoved.add { |_s, args| order << [:collection, args.GameComponent.equal?(subject)] }
    subject.Disposed.add { |_s, _a| order << [:component, true] }

    subject.Dispose
    assert_equal [[:collection, true], [:component, true]], order
  end

  # There is no disposed flag anywhere in the type.
  def test_dispose_is_not_idempotent_and_raises_disposed_every_time
    subject = component
    @game.Components.Add(subject)
    raised = 0
    subject.Disposed.add { |_s, _a| raised += 1 }

    subject.Dispose
    assert_equal 1, raised
    subject.Dispose
    assert_equal 2, raised, "no flag suppresses the second pass"
    subject.Dispose
    assert_equal 3, raised
    assert_equal 0, @game.Components.Count
  end

  # `if (!disposing) return;` is the first instruction.
  def test_dispose_false_does_nothing_at_all
    subject = component
    @game.Components.Add(subject)
    raised = 0
    subject.Disposed.add { |_s, _a| raised += 1 }

    assert_nil subject.Dispose(false)
    assert_equal 1, @game.Components.Count, "still in the collection"
    assert_equal 0, raised
  end

  # Both CLR overloads are retained in the static contract; Ruby carries them as one method.
  def test_both_dispose_overloads_are_in_the_static_contract
    target = SIGNATURES.fetch("types").find { |type| type.fetch("name") == NAME }
    disposes = target.fetch("members").select { |member| member.fetch("name") == "Dispose" }
    assert_equal 2, disposes.length
    assert_equal [[], ["System.Boolean"]],
                 disposes.map { |member| member.fetch("parameters").map { |p| p.fetch("type") } }.sort_by(&:length)
    assert_equal %w[protected public].sort, disposes.map { |member| member.fetch("access") }.sort
    # Both are selected, so the contract's overload count matches the reference and the type
    # carries no overload diagnostic of its own.
    refute(STRICT.fetch("details").fetch("OVERLOAD_MAPPING_MISMATCH")
                 .any? { |label| label.start_with?("#{NAME}::") })
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)

    # One Ruby method, dispatching on arity: `disposing` is optional and defaults to the public
    # overload's argument.
    assert_equal(-1, F::GameComponent.instance_method(:Dispose).arity)
  end

  # `lock (this)` is Monitor.Enter, which is reentrant: a Disposed handler disposing the same
  # component re-enters rather than deadlocking.
  def test_the_dispose_lock_is_reentrant
    subject = component
    @game.Components.Add(subject)
    depth = 0
    reached = 0
    subject.Disposed.add do |_s, _a|
      reached += 1
      next if depth.positive?

      depth += 1
      subject.Dispose
    end

    subject.Dispose
    assert_equal 2, reached, "the nested Dispose completed rather than deadlocking"
  end

  # `Dispose()` skips the removal when Game is null and still raises Disposed.
  def test_disposing_a_component_with_no_game_still_raises_disposed
    subject = component(nil)
    raised = 0
    subject.Disposed.add { |_s, _a| raised += 1 }
    subject.Dispose
    assert_equal 1, raised
  end

  # A component that was never added: `Remove` answers false, is discarded, and Disposed fires.
  def test_disposing_a_component_that_was_never_added_is_harmless
    subject = component
    raised = 0
    subject.Disposed.add { |_s, _a| raised += 1 }
    subject.Dispose
    assert_equal 1, raised
    assert_equal 0, @game.Components.Count
  end

  # ---------------------------------------------------------------------------------- Finalize

  # `Finalize` is `Dispose(false)`, which returns at its first instruction, so the CLR finalizer for
  # this type does nothing observable — and Ruby's GC never calls it, because nothing registers one.
  def test_finalize_does_nothing_and_no_ruby_finalizer_is_registered
    subject = component
    @game.Components.Add(subject)
    raised = 0
    subject.Disposed.add { |_s, _a| raised += 1 }

    assert_nil subject.__send__(:Finalize)
    assert_equal 1, @game.Components.Count
    assert_equal 0, raised

    # No ObjectSpace finalizer is registered anywhere in the binding, and no GC.SuppressFinalize
    # analogue was invented -- there is nothing to suppress.
    code = ROOT.glob("lib/**/*.rb").flat_map do |path|
      path.read.lines.reject { |line| line.strip.start_with?("#") }
    end
    refute(code.any? { |line| line.include?("define_finalizer") })
    refute(code.any? { |line| line.include?("SuppressFinalize") })
  end

  # ------------------------------------------------------------------- the engine, with real ones

  def test_a_real_component_is_ordered_updated_and_reordered_by_the_engine
    log = []
    first = Counting.new(@game)
    second = Counting.new(@game)
    first.UpdateOrder = 2
    second.UpdateOrder = 1
    [first, second].each { |value| @game.Components.Add(value) }

    @game.__send__(:Update, @time)
    assert_equal %i[update], first.log
    assert_equal %i[update], second.log
    assert_equal [second, first], @game.instance_variable_get(:@updateable_components)

    first.UpdateOrder = 0
    assert_equal [first, second], @game.instance_variable_get(:@updateable_components)
    _ = log
  end

  def test_a_disabled_component_is_skipped_by_the_base_update_pass
    subject = Counting.new(@game)
    subject.Enabled = false
    @game.Components.Add(subject)
    @game.__send__(:Update, @time)
    assert_empty subject.log

    subject.Enabled = true
    @game.__send__(:Update, @time)
    assert_equal %i[update], subject.log
  end

  def test_a_component_added_before_initialize_is_initialised_by_the_base_initialize
    subject = Counting.new(@game)
    @game.Components.Add(subject)
    assert_empty subject.log
    @game.__send__(:Initialize)
    assert_equal %i[initialize], subject.log
  end

  # A GameComponent is not an IDrawable, so it never reaches the draw list.
  def test_a_game_component_is_never_drawn
    subject = Counting.new(@game)
    @game.Components.Add(subject)
    @game.__send__(:Draw, @time)
    assert_empty subject.log
    assert_empty @game.instance_variable_get(:@drawable_components)
  end

  # ----------------------------------------------------------------------- Game disposes its own

  # `Game.Dispose(bool)` copies Components into an array and disposes each entry, which is what
  # makes it safe: every component's own Dispose removes it from the live collection.
  def test_game_dispose_disposes_every_component_over_a_snapshot
    disposed = []
    components = 3.times.map do
      value = component
      value.Disposed.add { |sender, _a| disposed << sender }
      @game.Components.Add(value)
      value
    end

    @game.Dispose
    assert_equal components, disposed, "every one, in collection order"
    assert_equal 0, @game.Components.Count
    @game = nil
  end

  # `x is IDisposable` has no nominal Ruby analogue: the collapse says the contract survives as the
  # member, so a component that declares no Dispose is simply skipped.
  def test_a_component_without_a_dispose_member_is_skipped_by_game_dispose
    plain = Class.new do
      include Microsoft::Xna::Framework::IGameComponent
      def Initialize = nil
    end.new
    disposable = component
    raised = 0
    disposable.Disposed.add { |_s, _a| raised += 1 }
    @game.Components.Add(plain)
    @game.Components.Add(disposable)

    @game.Dispose
    assert_equal 1, raised
    @game = nil
  end

  # ---------------------------------------------------------------------------- the scoreboard

  def test_the_milestone_completed_exactly_one_type_and_closed_no_game_member
    # Foundation 40 added Graphics::IGraphicsDeviceService: one type, five identities, four of them
    # events on a fifth owner. What this milestone owns -- Game's remainder and the partial count --
    # is what stayed put.
    assert_equal 142, STRICT.fetch("TARGET_TYPES")
    assert_equal 136, STRICT.fetch("COMPLETE_TYPES")
    assert_equal 115, STRICT.fetch("MISSING_TYPES")
    assert_equal 6, STRICT.fetch("PARTIAL_TYPES")
    assert_equal 130, STRICT.fetch("MISSING_MEMBER"), "Game's remainder is unchanged"
    assert_equal 13, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal 5, STRICT.fetch("EVENT_OWNER_TYPES")
    assert_equal 0, STRICT.fetch("UNEXPECTED_MEMBER")
    assert_equal 0, STRICT.fetch("INTERNAL_TYPE_LEAK")
    assert_equal 0, STRICT.fetch("UNMEASURED_STRUCTURAL_CATEGORY")

    # Game's own Dispose(Boolean), Finalize and Disposed stay deferred: only the component pass of
    # Dispose belongs to this slice.
    remainder = STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
    %w[Dispose Finalize Disposed].each do |name|
      assert(remainder.any? { |entry| entry.include?("::#{name} ") }, name)
    end
  end
end
