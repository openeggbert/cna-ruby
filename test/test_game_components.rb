# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "../lib/cna"

# Foundation 37 — `Game.Components`, `Game.Services`, and the managed component engine.
#
# Every behavioural claim is derived from the pinned `Microsoft.Xna.Framework.Game.dll` IL
# (SHA-256 b5dffdd8…) and the admitted mscorlib, never from another binding.
#
# The decision this milestone rests on: `Components`, `Services` and the four private lists behind
# them are **pure managed state**. CNA owns the native host, the frame loop and the device; it does
# not own the component list, and nothing here routes a component through the C ABI.
#
# The Ruby consequence that matters: `super` is the analogue of `base.Update(gameTime)`. The host
# invokes the virtual method once and never runs the base itself, so a subclass chooses whether,
# when and how many times the base component pass happens — and omitting `super` really suppresses
# it.
class GameComponentsTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  F = Microsoft::Xna::Framework
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read)
  REFERENCE = JSON.parse(ROOT.join("tools", "api_compat", "reference", "xna40-windows-runtime-contract.json").read)

  # Fixtures implementing the XNA contracts directly, so nothing here depends on `GameComponent`,
  # which is a later milestone.
  class Bare
    include Microsoft::Xna::Framework::IGameComponent

    attr_reader :label, :log

    def initialize(label, log = [])
      @label = label
      @log = log
    end

    def Initialize = @log << [:initialize, @label]
  end

  class Updateable < Bare
    extend CNA::Runtime::EventOwner
    include Microsoft::Xna::Framework::IUpdateable

    xna_event :EnabledChanged
    xna_event :UpdateOrderChanged

    attr_reader :Enabled, :UpdateOrder

    def initialize(label, log = [], order: 0, enabled: true)
      super(label, log)
      @Enabled = enabled
      @UpdateOrder = order
      @on_update = nil
    end

    def on_update(&block)
      @on_update = block
      self
    end

    def Update(game_time)
      @log << [:update, @label]
      @on_update&.call(game_time)
      nil
    end

    def Enabled=(value)
      return if @Enabled == value

      @Enabled = value
      self.EnabledChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
    end

    def UpdateOrder=(value)
      return if @UpdateOrder == value

      @UpdateOrder = value
      self.UpdateOrderChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
    end
  end

  class Drawable < Updateable
    extend CNA::Runtime::EventOwner
    include Microsoft::Xna::Framework::IDrawable

    xna_event :VisibleChanged
    xna_event :DrawOrderChanged

    attr_reader :Visible, :DrawOrder

    def initialize(label, log = [], order: 0, draw_order: 0, visible: true, enabled: true)
      super(label, log, order: order, enabled: enabled)
      @Visible = visible
      @DrawOrder = draw_order
      @on_draw = nil
    end

    def on_draw(&block)
      @on_draw = block
      self
    end

    def Draw(game_time)
      @log << [:draw, @label]
      @on_draw&.call(game_time)
      nil
    end

    def Visible=(value)
      return if @Visible == value

      @Visible = value
      self.VisibleChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
    end

    def DrawOrder=(value)
      return if @DrawOrder == value

      @DrawOrder = value
      self.DrawOrderChanged.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
    end
  end

  def setup
    @game = F::Game.new
    @time = F::GameTime.new
  end

  def teardown
    @game&.Dispose
  rescue StandardError
    nil
  end

  def update = @game.__send__(:Update, @time)
  def draw = @game.__send__(:Draw, @time)
  def initialize! = @game.__send__(:Initialize)
  def in_run!(value) = @game.instance_variable_set(:@in_run, value)
  def updateables = @game.instance_variable_get(:@updateable_components)
  def drawables = @game.instance_variable_get(:@drawable_components)
  def pending = @game.instance_variable_get(:@not_yet_initialized)

  # ------------------------------------------------------------------------------- the identities

  def test_both_properties_are_selected_and_complete
    game = STRICT.fetch("partialTypes").fetch("Microsoft.Xna.Framework.Game")
    refute(game.any? { |entry| entry.include?("::Components") })
    refute(game.any? { |entry| entry.include?("::Services") })
    assert_equal 21, game.length

    reference = REFERENCE.fetch("types").find { |type| type.fetch("name") == "Microsoft.Xna.Framework.Game" }
    %w[Components Services].each do |name|
      member = reference.fetch("members").find { |entry| entry.fetch("name") == name }
      assert_equal "property", member.fetch("kind")
      assert member.fetch("get")
      refute member.fetch("set"), "#{name} is read-only in the contract"
      refute F::Game.method_defined?(:"#{name}="), "no writer may exist"
    end
  end

  # `get_Components` and `get_Services` are one `ldfld` each: the same object, every time, for the
  # life of the Game.
  def test_each_getter_answers_the_same_object_every_time
    assert_instance_of F::GameComponentCollection, @game.Components
    assert_instance_of F::GameServiceContainer, @game.Services
    assert_same @game.Components, @game.Components
    assert_same @game.Services, @game.Services

    # And two Games never share either.
    other = F::Game.new
    refute_same @game.Components, other.Components
    refute_same @game.Services, other.Services
  ensure
    other&.Dispose
  end

  # They exist from the moment the constructor returns and are not fallible: neither goes through
  # the native host, so neither needs one.
  def test_neither_requires_a_native_host
    assert_nil @game.instance_variable_get(:@host)
    assert_equal 0, @game.Components.Count
    assert_nil @game.Services.GetService(Comparable)
    @game.Components.Add(Bare.new(:a))
    assert_equal 1, @game.Components.Count
    assert_nil @game.instance_variable_get(:@host), "no host was created by using them"
  end

  # The `.ctor` allocates `gameServices` in its field-initialiser prologue and `gameComponents`
  # after the base constructor, so Services exists first. Both exist by the time it returns.
  def test_services_is_allocated_before_components
    order = []
    services = F::GameServiceContainer
    collection = F::GameComponentCollection
    services.define_singleton_method(:new) { |*| order << :services; super() }
    collection.define_singleton_method(:new) { |*| order << :components; super() }
    game = F::Game.new
    assert_equal %i[services components], order
    refute_nil game.Services
    refute_nil game.Components
  ensure
    services&.singleton_class&.__send__(:remove_method, :new)
    collection&.singleton_class&.__send__(:remove_method, :new)
    game&.Dispose
  end

  # The constructor subscribes both handlers, and they are private: no consumer-facing identity was
  # added and the collection's own events stay the only public surface.
  def test_the_constructor_attaches_both_collection_handlers
    %i[game_component_added game_component_removed].each do |handler|
      assert F::Game.private_method_defined?(handler), handler
      refute F::Game.public_method_defined?(handler), handler
      refute F::Game.protected_method_defined?(handler), handler
    end

    component = Updateable.new(:a)
    @game.Components.Add(component)
    assert_equal [component], updateables
    @game.Components.Remove(component)
    assert_empty updateables
  end

  # Nothing routes a component through the C ABI.
  def test_the_component_engine_adds_no_native_binding
    assert_equal 39, CNA::Native::Manifest::FUNCTIONS.length
    assert_equal 59, CNA::Native::Manifest::CONSTANTS.length
    refute(CNA::Native::Manifest::FUNCTIONS.any? { |entry| entry.symbol.to_s.include?("component") })
  end

  # ----------------------------------------------------------------- add before / after Initialize

  # `GameComponentAdded` queues when `inRun` is false and initialises on the spot when it is true.
  def test_a_component_added_before_initialize_is_queued_not_initialised
    log = []
    component = Bare.new(:a, log)
    @game.Components.Add(component)
    assert_equal [component], pending
    assert_empty log, "queued, not initialised"

    initialize!
    assert_empty pending
    assert_equal [[:initialize, :a]], log
  end

  def test_a_component_added_after_the_flag_is_raised_is_initialised_immediately
    log = []
    initialize!
    in_run!(true)
    @game.Components.Add(Bare.new(:a, log))
    assert_equal [[:initialize, :a]], log
    assert_empty pending, "nothing is queued once the game is running"
  end

  # The drain loop re-reads `Count` and always takes index 0, so a component another component's
  # `Initialize` adds is picked up by the same loop.
  def test_a_component_added_during_initialisation_is_drained_by_the_same_loop
    log = []
    late = Bare.new(:late, log)
    first = Bare.new(:first, log)
    first.define_singleton_method(:Initialize) do
      log << [:initialize, :first]
      @game_ref.Components.Add(late)
    end
    first.instance_variable_set(:@game_ref, @game)

    @game.Components.Add(first)
    initialize!
    assert_equal [[:initialize, :first], [:initialize, :late]], log
    assert_empty pending
  end

  # The element is removed **after** its Initialize returns, so a raising component stays at the
  # head of the queue and the drain can be resumed.
  def test_a_component_whose_initialize_raises_stays_at_the_head_of_the_queue
    log = []
    bad = Bare.new(:bad, log)
    bad.define_singleton_method(:Initialize) { raise "bad" }
    good = Bare.new(:good, log)
    @game.Components.Add(bad)
    @game.Components.Add(good)

    assert_raises(RuntimeError) { initialize! }
    assert_equal [bad, good], pending
    assert_empty log

    bad.define_singleton_method(:Initialize) { log << [:initialize, :bad] }
    initialize!
    assert_equal [[:initialize, :bad], [:initialize, :good]], log
    assert_empty pending
  end

  # Removing a queued component before initialisation removes it from the queue too.
  def test_removing_a_queued_component_unqueues_it
    log = []
    component = Bare.new(:a, log)
    @game.Components.Add(component)
    @game.Components.Remove(component)
    assert_empty pending
    initialize!
    assert_empty log
  end

  # `if (!inRun) notYetInitialized.Remove(...)` — once running, the queue is not touched, and the
  # removal pops its result so removing something never queued is harmless.
  def test_removing_a_component_while_running_leaves_the_queue_alone
    stale = Bare.new(:stale)
    @game.Components.Add(stale)
    in_run!(true)
    @game.Components.Remove(stale)
    assert_equal [stale], pending, "the queue is only maintained while inRun is false"
  end

  # ---------------------------------------------------------------------------- ordered insertion

  # BinarySearch answers 0 only for an *equal* component, never for one that merely shares an order,
  # so the search is a lower bound and the walk that follows turns it into an upper bound: equal
  # orders keep insertion order.
  def test_components_are_ordered_by_update_order_and_stable_among_equals
    first = Updateable.new(:first, order: 5)
    second = Updateable.new(:second, order: 5)
    third = Updateable.new(:third, order: 5)
    low = Updateable.new(:low, order: 1)
    high = Updateable.new(:high, order: 9)

    [first, second, third].each { |component| @game.Components.Add(component) }
    @game.Components.Add(high)
    @game.Components.Add(low)

    assert_equal %i[low first second third high], updateables.map(&:label)
  end

  def test_drawables_are_ordered_by_draw_order_independently_of_update_order
    a = Drawable.new(:a, order: 9, draw_order: 1)
    b = Drawable.new(:b, order: 1, draw_order: 9)
    @game.Components.Add(a)
    @game.Components.Add(b)

    assert_equal %i[b a], updateables.map(&:label)
    assert_equal %i[a b], drawables.map(&:label)
  end

  # A component that is only an IGameComponent reaches neither list, and one that is both reaches
  # both.
  def test_only_the_contracts_a_component_declares_put_it_in_a_list
    bare = Bare.new(:bare)
    updateable = Updateable.new(:updateable)
    drawable = Drawable.new(:drawable)
    [bare, updateable, drawable].each { |component| @game.Components.Add(component) }

    assert_equal %i[updateable drawable], updateables.map(&:label)
    assert_equal %i[drawable], drawables.map(&:label)
    assert_equal 3, @game.Components.Count
  end

  # Removal takes it out of every list it reached and unsubscribes the order-changed handler, so a
  # later order change no longer reorders anything.
  def test_removal_unsubscribes_the_order_changed_handler
    component = Updateable.new(:a, order: 1)
    other = Updateable.new(:b, order: 2)
    @game.Components.Add(component)
    @game.Components.Add(other)
    @game.Components.Remove(component)
    assert_equal %i[b], updateables.map(&:label)

    component.UpdateOrder = 99
    assert_equal %i[b], updateables.map(&:label), "a removed component must not reappear"
  end

  # ---------------------------------------------------------------------------- order changes

  # `UpdateableUpdateOrderChanged` removes and reinserts, taking the component from `sender`.
  def test_changing_update_order_reorders_the_list
    a = Updateable.new(:a, order: 1)
    b = Updateable.new(:b, order: 2)
    c = Updateable.new(:c, order: 3)
    [a, b, c].each { |component| @game.Components.Add(component) }
    assert_equal %i[a b c], updateables.map(&:label)

    a.UpdateOrder = 10
    assert_equal %i[b c a], updateables.map(&:label)

    c.UpdateOrder = 0
    assert_equal %i[c b a], updateables.map(&:label)
  end

  # The reinsertion uses the same upper-bound walk, so a component moved onto an existing order
  # lands after everything already there.
  def test_a_reordered_component_lands_after_every_component_that_already_has_that_order
    a = Updateable.new(:a, order: 1)
    b = Updateable.new(:b, order: 5)
    c = Updateable.new(:c, order: 5)
    [a, b, c].each { |component| @game.Components.Add(component) }
    assert_equal %i[a b c], updateables.map(&:label)

    a.UpdateOrder = 5
    assert_equal %i[b c a], updateables.map(&:label)
  end

  def test_changing_draw_order_reorders_only_the_drawable_list
    a = Drawable.new(:a, order: 1, draw_order: 1)
    b = Drawable.new(:b, order: 2, draw_order: 2)
    @game.Components.Add(a)
    @game.Components.Add(b)

    a.DrawOrder = 9
    assert_equal %i[b a], drawables.map(&:label)
    assert_equal %i[a b] , updateables.map(&:label), "the update order was not touched"
  end

  # Setting the same value raises no event, so nothing reorders.
  def test_setting_the_same_order_changes_nothing
    a = Updateable.new(:a, order: 1)
    b = Updateable.new(:b, order: 1)
    @game.Components.Add(a)
    @game.Components.Add(b)
    a.UpdateOrder = 1
    assert_equal %i[a b], updateables.map(&:label), "no event, so no reinsertion"
  end

  # An exception from a component's order getter surfaces as the CLR's
  # InvalidOperationException("InvalidOperation_IComparerFailed"), which maps to RuntimeError.
  def test_a_failing_order_getter_surfaces_as_a_runtime_error
    @game.Components.Add(Updateable.new(:present, order: 1))
    bad = Updateable.new(:bad, order: 2)
    bad.define_singleton_method(:UpdateOrder) { raise TypeError, "no order" }
    error = assert_raises(RuntimeError) { @game.Components.Add(bad) }
    assert_instance_of TypeError, error.cause
  end

  # --------------------------------------------------------------------------- the base Update

  def test_the_base_update_visits_enabled_components_in_order
    log = []
    a = Updateable.new(:a, log, order: 2)
    b = Updateable.new(:b, log, order: 1)
    [a, b].each { |component| @game.Components.Add(component) }

    update
    assert_equal [[:update, :b], [:update, :a]], log
  end

  # `Enabled` is read immediately before each call rather than snapshotted, so a component disabled
  # earlier in the same pass is skipped in that pass.
  def test_enabled_is_read_at_call_time_not_snapshotted
    log = []
    later = Updateable.new(:later, log, order: 2)
    first = Updateable.new(:first, log, order: 1).on_update { later.Enabled = false }
    [first, later].each { |component| @game.Components.Add(component) }

    update
    assert_equal [[:update, :first]], log
  end

  def test_a_disabled_component_is_skipped_and_re_enabling_it_restores_it
    log = []
    component = Updateable.new(:a, log, enabled: false)
    @game.Components.Add(component)
    update
    assert_empty log

    component.Enabled = true
    update
    assert_equal [[:update, :a]], log
  end

  # The pass walks a snapshot, so a component added or removed during it takes effect next frame.
  def test_mutation_during_the_update_pass_takes_effect_from_the_next_pass
    log = []
    late = Updateable.new(:late, log, order: 9)
    added = false
    first = Updateable.new(:first, log, order: 1).on_update do
      next if added

      added = true
      @game.Components.Add(late)
    end
    @game.Components.Add(first)

    update
    assert_equal [[:update, :first]], log, "the snapshot did not grow"
    assert_equal %i[first late], updateables.map(&:label)

    log.clear
    update
    assert_equal [[:update, :first], [:update, :late]], log
  end

  def test_a_component_removed_during_the_pass_is_still_updated_in_that_pass
    log = []
    victim = Updateable.new(:victim, log, order: 9)
    first = Updateable.new(:first, log, order: 1).on_update { @game.Components.Remove(victim) }
    # Remove answers false the second time; nothing else changes.
    [first, victim].each { |component| @game.Components.Add(component) }

    update
    assert_equal [[:update, :first], [:update, :victim]], log
    log.clear
    update
    assert_equal [[:update, :first]], log
  end

  # There is no try/finally around the Clear, so a raising component leaves the snapshot populated
  # and the next pass appends to it. XNA's behaviour, reproduced rather than corrected.
  def test_a_raising_component_leaves_the_snapshot_list_populated
    log = []
    bad = Updateable.new(:bad, log).on_update { raise "bad" }
    @game.Components.Add(bad)

    assert_raises(RuntimeError) { update }
    assert_equal [bad], @game.instance_variable_get(:@currently_updating_components)
  end

  # ----------------------------------------------------------------------------- the base Draw

  def test_the_base_draw_visits_visible_components_in_draw_order
    log = []
    a = Drawable.new(:a, log, draw_order: 2)
    b = Drawable.new(:b, log, draw_order: 1)
    [a, b].each { |component| @game.Components.Add(component) }

    draw
    assert_equal [[:draw, :b], [:draw, :a]], log
  end

  def test_visible_is_read_at_call_time_and_a_hidden_component_is_skipped
    log = []
    later = Drawable.new(:later, log, draw_order: 2)
    first = Drawable.new(:first, log, draw_order: 1).on_draw { later.Visible = false }
    [first, later].each { |component| @game.Components.Add(component) }

    draw
    assert_equal [[:draw, :first]], log
  end

  # No device is required to observe the ordering: the base decides who is visited and each
  # component's own Draw decides what, if anything, it renders.
  def test_the_draw_pass_needs_no_graphics_device
    assert_nil @game.GraphicsDevice
    log = []
    @game.Components.Add(Drawable.new(:a, log))
    draw
    assert_equal [[:draw, :a]], log
  end

  def test_update_and_draw_are_independent_passes
    log = []
    component = Drawable.new(:a, log, enabled: false, visible: true)
    @game.Components.Add(component)
    update
    draw
    assert_equal [[:draw, :a]], log
  end

  # ---------------------------------------------------------------------------- Ruby `super`

  # This is the whole architectural point: the base component pass is what `super` runs, and a
  # subclass decides whether it happens at all.
  # Each of the three overrides `Game#Update` directly, so `super` reaches the base implementation
  # itself rather than another override.
  class Recording < Microsoft::Xna::Framework::Game
    attr_reader :calls

    def initialize
      super
      @calls = []
    end
  end

  class Suppressing < Recording
    def Update(game_time)
      @calls << :before
      @calls << :after
    end
  end

  class Calling < Recording
    def Update(game_time)
      @calls << :before
      super(game_time)
      @calls << :after
    end
  end

  class Twice < Recording
    def Update(game_time)
      super(game_time)
      super(game_time)
    end
  end

  def test_omitting_super_suppresses_the_base_component_pass
    log = []
    game = Suppressing.new
    game.Components.Add(Updateable.new(:a, log))
    game.__send__(:Update, @time)
    assert_equal %i[before after], game.calls
    assert_empty log, "the base pass did not run"
  ensure
    game&.Dispose
  end

  def test_calling_super_runs_the_base_pass_between_the_subclass_work
    log = []
    game = Calling.new
    game.Components.Add(Updateable.new(:a, log).on_update { log << [:during, :marker] })
    game.__send__(:Update, @time)
    assert_equal %i[before after], game.calls
    assert_equal [[:update, :a], [:during, :marker]], log
  ensure
    game&.Dispose
  end

  # A subclass may run the base more than once, exactly as a CLR override may, and each run is a
  # complete pass.
  def test_a_subclass_may_run_the_base_pass_twice
    log = []
    game = Twice.new
    game.Components.Add(Updateable.new(:a, log))
    game.__send__(:Update, @time)
    assert_equal [[:update, :a], [:update, :a]], log
  ensure
    game&.Dispose
  end

  # No parallel base-call API was invented: Ruby inheritance is the whole mechanism.
  def test_no_game_base_update_helper_exists
    %i[GameBaseUpdate GameBaseDraw GameBaseInitialize base_update base_draw base_initialize
       BaseUpdate BaseDraw BaseInitialize].each do |invented|
      refute F::Game.method_defined?(invented), invented
      refute F::Game.private_method_defined?(invented), invented
      refute F::Game.respond_to?(invented), invented
    end
  end

  # The base hooks keep the CLR's protected visibility, so a consumer cannot drive the loop by
  # hand; a subclass reaches them through `super` and through defining its own override.
  def test_the_lifecycle_hooks_stay_protected
    %i[Initialize LoadContent UnloadContent BeginRun EndRun Update Draw BeginDraw EndDraw]
      .each do |hook|
      assert F::Game.protected_method_defined?(hook), hook
      refute F::Game.public_method_defined?(hook), hook
    end
    assert_raises(NoMethodError) { @game.Update(@time) }
  end

  # ------------------------------------------------------------------- the hooks that stay no-ops

  # Measured, not assumed: four of the nine are `{ ret }` in the pinned IL and stay no-ops.
  def test_the_hooks_whose_il_is_a_bare_ret_stay_no_ops
    assert_nil @game.__send__(:BeginRun)
    assert_nil @game.__send__(:EndRun)
    assert_nil @game.__send__(:LoadContent)
    assert_nil @game.__send__(:UnloadContent)
    assert_nil @game.__send__(:EndDraw)
    assert_equal true, @game.__send__(:BeginDraw)
  end

  def test_update_and_draw_still_require_a_game_time
    assert_raises(TypeError) { @game.__send__(:Update, nil) }
    assert_raises(TypeError) { @game.__send__(:Draw, :not_a_game_time) }
  end

  # ------------------------------------------------------- the native host drives the same order

  # The callback-order audit, run against the real CNA library rather than read out of its header.
  #
  # XNA:  CreateDevice -> Initialize() [-> LoadContent() when a device service exists]
  #       -> inRun = true -> BeginRun() -> Update() -> loop{ Update, BeginDraw, Draw, EndDraw }
  #       -> EndRun(), and the finally clears inRun.
  # CNA:  initialize -> load_content -> begin_run -> update -> begin_draw -> draw -> end_draw ...
  #       -> exiting -> end_run -> unload_content.
  #
  # The one structural difference is *who* calls LoadContent, and it costs nothing here: XNA's base
  # `Initialize` calls it only when `Services` holds an `IGraphicsDeviceService`, which is a missing
  # type this binding has no key for, so the guard is false and the host's separate `load_content`
  # callback is the only one. Nothing is called twice and nothing is skipped.
  class Ordered < Microsoft::Xna::Framework::Game
    attr_reader :order, :flags

    def initialize
      super
      @order = []
      @flags = []
      @frames = 0
    end

    def record(name)
      @order << name
      @flags << [name, instance_variable_get(:@in_run)]
      nil
    end

    def Initialize    = (record(:Initialize); super)
    def LoadContent   = (record(:LoadContent); super)
    def BeginRun      = (record(:BeginRun); super)
    def BeginDraw     = (record(:BeginDraw); super)
    def Draw(time)    = (record(:Draw); super)
    def EndDraw       = (record(:EndDraw); super)
    def EndRun        = (record(:EndRun); super)
    def UnloadContent = (record(:UnloadContent); super)

    def Update(time)
      record(:Update)
      super
      @frames += 1
      self.Exit if @frames >= 2
    end
  end

  def test_the_native_host_delivers_the_canonical_xna_order
    game = Ordered.new
    game.Run
    assert_equal %i[Initialize LoadContent BeginRun Update BeginDraw Draw EndDraw Update EndRun],
                 game.order

    # UnloadContent is delivered by teardown rather than by the run, which is where XNA puts it
    # too: `Game.Dispose` is what unloads content, not the end of the loop.
    game.Dispose
    assert_equal :UnloadContent, game.order.last
  ensure
    game&.Dispose
  end

  # XNA raises `inRun` in `RunGame`, not inside `Initialize`, so it survives a subclass that
  # overrides `Initialize` without calling `super`. The measured equivalent here is "after the last
  # managed step XNA performs before raising it", which is `LoadContent` -- in XNA that call sits
  # inside `Initialize`'s own body, ahead of the assignment.
  def test_the_in_run_flag_is_raised_after_load_content_and_cleared_after_end_run
    game = Ordered.new
    refute game.instance_variable_get(:@in_run), "false until the host starts"
    game.Run

    assert_equal [[:Initialize, false], [:LoadContent, false], [:BeginRun, true]],
                 game.flags.first(3)
    assert(game.flags.select { |name, _| name == :Update }.all? { |_, flag| flag })
    assert_equal [:EndRun, true], game.flags.find { |name, _| name == :EndRun }
    refute game.instance_variable_get(:@in_run), "cleared once the run is over"
  ensure
    game&.Dispose
  end

  # A component added before the run is queued and initialised by the base `Initialize`; one added
  # during the run is initialised on the spot.
  class Lifecycle < Microsoft::Xna::Framework::Game
    attr_reader :log

    def initialize
      super
      @log = []
      @frames = 0
      @added = false
    end

    def Update(time)
      super
      @frames += 1
      unless @added
        @added = true
        self.Components.Add(GameComponentsTest::Updateable.new(:late, @log))
      end
      self.Exit if @frames >= 3
    end
  end

  def test_a_component_added_during_the_run_is_initialised_immediately_and_updates_next_frame
    game = Lifecycle.new
    early = Updateable.new(:early, game.log)
    game.Components.Add(early)
    game.Run

    kinds = game.log.map(&:first)
    assert_equal :initialize, kinds.first, "the queued component is initialised by base Initialize"
    assert_equal [[:initialize, :early]], game.log.select { |kind, _| kind == :initialize }.first(1)
    assert_includes game.log, [:initialize, :late]
    assert_includes game.log, [:update, :late]

    # The late component was initialised before it was ever updated.
    assert_operator game.log.index([:initialize, :late]), :<, game.log.index([:update, :late])
  ensure
    game&.Dispose
  end

  # The host invokes the virtual method once per frame. A subclass that omits `super` therefore
  # sees no component pass at all, and no second base pass happens behind its back.
  class HostSuppressing < Microsoft::Xna::Framework::Game
    attr_reader :log, :updates

    def initialize
      super
      @log = []
      @updates = 0
      @frames = 0
    end

    def Update(time)
      @updates += 1
      @frames += 1
      self.Exit if @frames >= 2
    end
  end

  def test_the_host_never_runs_the_base_pass_behind_an_override
    game = HostSuppressing.new
    game.Components.Add(Updateable.new(:a, game.log))
    game.Run

    assert_operator game.updates, :>=, 2
    assert_empty(game.log.select { |kind, _| kind == :update },
                 "no base component pass ran without super")
  ensure
    game&.Dispose
  end
end
