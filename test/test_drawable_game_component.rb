# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `DrawableGameComponent`, and the producer claim that kept it deferred for eleven milestones.
#
# `docs/graphics-device-service-producer-audit.md` concluded that this binding could register no
# `IGraphicsDeviceService` in `Game.Services` without "a material Game/graphics lifecycle redesign".
# Re-reading `GraphicsDeviceManager`'s own constructor IL is what settled it: the registration is
# two `AddService` calls into a **managed dictionary** that nothing in CNA reads, and this manager
# has answered every member of the service contract since Foundation 96 measured its four events to
# be relays of the device's own. The audit was right that making the managed container the one
# CNA's lifecycle runs against would be a redesign, and wrong that this is that.
class DrawableGameComponentTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.DrawableGameComponent"

  # A component that records every lifecycle call it receives, in order.
  class Recorder < F::DrawableGameComponent
    attr_reader :log

    def initialize(game)
      @log = []
      super
    end

    def Initialize
      @log << :initialize
      super
    end

    def Update(gameTime)
      @log << :update
      super
    end

    def Draw(_gameTime) = @log << :draw

    protected

    def LoadContent = @log << :load
    def UnloadContent = @log << :unload
  end

  class Host < F::Game
    attr_reader :component, :manager

    def initialize(frames = 2)
      super()
      @manager = F::GraphicsDeviceManager.new(self)
      @component = Recorder.new(self)
      self.Components.Add(@component)
      @frames = frames
      @seen = 0
    end

    def Update(gameTime)
      super
      @seen += 1
      self.Exit if @seen == @frames
    end
  end

  def with_game
    game = yield_game
    yield game
  ensure
    game&.Dispose
  end

  def yield_game = Host.new

  # ------------------------------------------------------------------ the surface

  def test_it_is_complete_and_left_the_frontier
    assert ReviewedScoreboard.complete?(STRICT, NAME)
    assert_equal 0, STRICT.fetch("localDiagnostics").fetch(NAME)
    assert_equal ReviewedScoreboard::COMPLETE_TYPES, STRICT.fetch("COMPLETE_TYPES")
    frontier = JSON.parse(ROOT.join("docs", "generated", "public-signature-dependency-report.json").read)
    refute_includes frontier.fetch("partialDependencySatisfiedCandidates").map { |e| e.fetch("name") }, NAME
  end

  def test_it_is_a_game_component_that_also_declares_idrawable
    assert_operator F::DrawableGameComponent, :<, F::GameComponent
    [F::IDrawable, F::IGameComponent, F::IUpdateable].each do |contract|
      assert_includes F::DrawableGameComponent.ancestors, contract, contract.to_s
    end
  end

  # ------------------------------------------------------------------ the producer

  # The correction, asserted directly: the manager registers itself under **both** service types,
  # which is what its constructor IL does.
  def test_the_manager_registers_itself_as_both_services
    game = F::Game.new
    assert_nil game.Services.GetService(G::IGraphicsDeviceService)
    assert_nil game.Services.GetService(F::IGraphicsDeviceManager)
    manager = F::GraphicsDeviceManager.new(game)
    assert_same manager, game.Services.GetService(G::IGraphicsDeviceService)
    assert_same manager, game.Services.GetService(F::IGraphicsDeviceManager)
    game.Dispose
  end

  # `if (game.Services.GetService(typeof(IGraphicsDeviceManager)) != null) throw
  # new ArgumentException(GraphicsDeviceManagerAlreadyPresent);` — checked before anything is built.
  def test_a_second_manager_is_refused
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    assert_raises(ArgumentError) { F::GraphicsDeviceManager.new(game) }
    game.Dispose
  end

  # `IGraphicsDeviceManager`'s three members are explicit implementations, so none is public.
  def test_the_managers_three_explicit_members_are_not_public
    %i[CreateDevice BeginDraw EndDraw].each do |name|
      refute F::GraphicsDeviceManager.public_method_defined?(name), name.to_s
      assert F::GraphicsDeviceManager.private_method_defined?(name), name.to_s
    end
  end

  # And with no manager at all, `Initialize` refuses exactly as XNA's does.
  def test_initialize_refuses_when_no_service_is_registered
    game = F::Game.new
    component = Recorder.new(game)
    error = assert_raises(RuntimeError) { component.Initialize }
    assert_equal "No Graphics Device Service", error.message
    assert_empty component.log - [:initialize]
    game.Dispose
  end

  # ------------------------------------------------------------------ the properties

  # `visible = true` is the constructor's **first** instruction, before the base constructor runs.
  def test_visible_starts_true_and_draw_order_zero
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    assert_equal true, component.Visible
    assert_equal 0, component.DrawOrder
    game.Dispose
  end

  # The same five instructions `Enabled` and `UpdateOrder` carry: same-value suppression first, the
  # field written before the notification, so a handler always sees the new value.
  def test_both_setters_suppress_a_same_value_write_and_notify_after_the_write
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    seen = []
    component.VisibleChanged.add(->(sender, args) { seen << [:visible, sender.Visible, args] })
    component.DrawOrderChanged.add(->(sender, args) { seen << [:order, sender.DrawOrder, args] })
    component.Visible = true
    component.DrawOrder = 0
    assert_empty seen, "a same-value write raises nothing at all"
    component.Visible = false
    component.DrawOrder = 7
    assert_equal [[:visible, false, CNA::Runtime::EventArgs::Empty],
                  [:order, 7, CNA::Runtime::EventArgs::Empty]], seen
    game.Dispose
  end

  def test_the_raisers_are_protected_and_take_a_sender_and_args
    %i[OnVisibleChanged OnDrawOrderChanged].each do |name|
      refute F::DrawableGameComponent.public_method_defined?(name), name.to_s
      assert F::DrawableGameComponent.protected_method_defined?(name), name.to_s
      assert_equal 2, F::DrawableGameComponent.instance_method(name).arity, name.to_s
    end
    %i[LoadContent UnloadContent].each do |name|
      refute F::DrawableGameComponent.public_method_defined?(name), name.to_s
      assert F::DrawableGameComponent.protected_method_defined?(name), name.to_s
    end
  end

  # ------------------------------------------------------------------ GraphicsDevice

  # `if (deviceService == null) throw new InvalidOperationException(
  #    PropertyCannotBeCalledBeforeInitialize)` — it refuses rather than answering nil.
  def test_the_device_refuses_before_initialize_and_is_the_services_afterwards
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    error = assert_raises(RuntimeError) { component.GraphicsDevice }
    assert_equal "This property cannot be called before Initialize().", error.message
    component.Initialize
    assert_same manager.GraphicsDevice, component.GraphicsDevice
    game.Dispose
  end

  # ------------------------------------------------------------------ Initialize

  # `base.Initialize()`, the lookup, the four subscriptions, then `LoadContent` because the service
  # already has a device — and the `initialized` guard makes a second call do nothing but the base.
  def test_initialize_loads_content_once_and_guards_the_second_call
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    component.Initialize
    assert_equal %i[initialize load], component.log
    component.Initialize
    assert_equal %i[initialize load initialize], component.log
    game.Dispose
  end

  # The four subscriptions are real: raising the device's own events reaches the component, and
  # `DeviceCreated` and `DeviceDisposing` are the two with a body.
  def test_the_four_device_subscriptions_are_the_ils
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    component.Initialize
    component.log.clear
    device = manager.GraphicsDevice
    device.__send__(:raise_DeviceResetting)
    device.__send__(:raise_DeviceReset)
    assert_empty component.log, "both reset handlers are bare rets"
    manager.__send__(:OnDeviceCreated, manager, CNA::Runtime::EventArgs::Empty)
    assert_equal %i[load], component.log
    device.__send__(:raise_Disposing)
    assert_equal %i[load unload], component.log
    game.Dispose
  end

  # ------------------------------------------------------------------ Draw and disposal

  # The whole lifecycle through a real game loop: the engine initializes the component, the service
  # loads its content, and `Update` and `Draw` reach it while it is enabled and visible.
  def test_the_game_loop_initializes_updates_and_draws_it
    skip "CNA_NATIVE_LIBRARY not supplied" if ENV["CNA_NATIVE_LIBRARY"].to_s.empty?

    game = Host.new
    begin
      game.Run
      assert_equal %i[initialize load], game.component.log.first(2)
      assert_includes game.component.log, :update
      assert_includes game.component.log, :draw
    ensure
      game.Dispose
    end
    assert_equal :unload, game.component.log.last
  end

  # `Visible = false` takes it out of the draw pass and leaves `Update` alone, which is the whole
  # difference between `IDrawable.Visible` and `IUpdateable.Enabled`.
  def test_an_invisible_component_still_updates
    skip "CNA_NATIVE_LIBRARY not supplied" if ENV["CNA_NATIVE_LIBRARY"].to_s.empty?

    game = Host.new
    game.component.Visible = false
    begin
      game.Run
      assert_includes game.component.log, :update
      refute_includes game.component.log, :draw
    ensure
      game.Dispose
    end
  end

  # `public virtual void Draw(GameTime)` is a bare `ret`: it validates nothing, not even a null.
  def test_the_base_draw_is_a_bare_ret
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    component = F::DrawableGameComponent.new(game)
    assert_nil component.Draw(nil)
    assert_nil component.Draw(F::GameTime.new)
    game.Dispose
  end

  # `if (!disposing) return; UnloadContent(); remove the four; base.Dispose(disposing);`
  def test_dispose_unloads_before_unsubscribing_and_dispose_false_does_neither
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    component.Initialize
    component.log.clear
    component.Dispose(false)
    assert_empty component.log, "Dispose(false) returns at the first instruction"
    component.Dispose
    assert_equal %i[unload], component.log
    # Unsubscribed: the device's Disposing no longer reaches it.
    manager.GraphicsDevice.__send__(:raise_Disposing)
    assert_equal %i[unload], component.log
    game.Dispose
  end

  # The base's `Dispose` removes it from `Game.Components` before raising `Disposed`, and this one
  # inherits both, so a component that disposes itself leaves the collection.
  def test_dispose_removes_it_from_the_collection_and_raises_disposed
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    component = Recorder.new(game)
    game.Components.Add(component)
    component.Initialize
    seen = []
    component.Disposed.add(->(_sender, _args) { seen << game.Components.Count })
    component.Dispose
    assert_equal [0], seen, "the removal happens before the notification"
    game.Dispose
  end
end
