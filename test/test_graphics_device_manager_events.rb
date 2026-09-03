# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "../lib/cna"

# `GraphicsDeviceManager`'s five events, their four raisers and `Dispose(Boolean)` — ten of the
# fifteen members `docs/graphics-device-service-producer-audit.md` deferred, closed **without one
# new native route**.
#
# The producer audit is correct about what it measured and its conclusion did not survive being
# re-measured for this family. What it measured is that a *managed* `IGraphicsDeviceService`
# producer cannot be registered: CNA's native `Game` is the XNA `Game`, its
# `cna_graphics_device_manager_create` registers the manager as both services in a container the C
# ABI deliberately gives no registration route to, and adding a second registration would duplicate
# the lifecycle rather than enable it. All of that still holds.
#
# None of it is about these ten. **Four of the five events are relays of the device's own**, and
# that is the IL rather than an interpretation: `CreateDevice` hooks four private handlers onto the
# device it has just made, each of which is one call to the matching `On…` raiser, and
# `HandleDeviceLost`'s body is a single `ret`. The device already carries every signal — Foundation
# 93 gave it them — so the manager needs no producer, no subscription and no route.
class GraphicsDeviceManagerEventsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.GraphicsDeviceManager"
  EVENTS = %i[DeviceCreated DeviceDisposing DeviceReset DeviceResetting Disposed].freeze
  RAISERS = %i[OnDeviceCreated OnDeviceDisposing OnDeviceReset OnDeviceResetting].freeze

  def test_the_ten_left_the_partial_remainder
    remainder = ReviewedScoreboard.outstanding(STRICT, NAME)
    (EVENTS + RAISERS + %i[Dispose]).each { |member| refute_includes remainder, member.to_s, member.to_s }
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_MANAGER_OUTSTANDING, remainder
    assert_equal 0, STRICT.fetch("EVENT_MAPPING_MISMATCH")
  end

  # The whole point: ten members and **no** new native surface.
  def test_no_native_route_was_added_for_any_of_them
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    %w[cna_graphics_device_manager_subscribe
       cna_graphics_device_manager_subscribe_preparing_device_settings
       cna_graphics_device_manager_subscribe_preparing_device_settings_ext
       cna_graphics_device_manager_create_device
       cna_graphics_device_manager_begin_draw
       cna_graphics_device_manager_end_draw].each { |absent| refute_includes symbols, absent }
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:functions), CNA::Native::Manifest::FUNCTIONS.length
    assert_equal NativeSurfaceCensus::REVIEWED.fetch(:callbacks), CNA::Native::Manifest::CALLBACKS.length
  end

  # One reader identity each; the raisers are `family` in XNA, so protected here.
  def test_the_shapes_are_the_ils
    EVENTS.each do |name|
      assert F::GraphicsDeviceManager.public_method_defined?(name), name.to_s
      refute F::GraphicsDeviceManager.method_defined?(:"#{name}="), "#{name}="
    end
    RAISERS.each do |name|
      refute F::GraphicsDeviceManager.public_method_defined?(name), name.to_s
      assert F::GraphicsDeviceManager.protected_method_defined?(name), name.to_s
      assert_equal 2, F::GraphicsDeviceManager.instance_method(name).arity, name.to_s
    end
    # XNA declares no `DeviceLost` on the manager, because `HandleDeviceLost` does nothing.
    refute F::GraphicsDeviceManager.method_defined?(:DeviceLost)
  end

  class EventGame < F::Game
    attr_reader :manager, :log

    def initialize
      @log = []
      super()
      @manager = F::GraphicsDeviceManager.new(self)
      EVENTS.each do |name|
        @manager.__send__(name).add(->(sender, args) { @log << [name, sender.equal?(@manager), args] })
      end
    end

    def Draw(_time)
      self.GraphicsDevice.Reset
    ensure
      self.Exit
    end
  end

  def native? = !ENV["CNA_NATIVE_LIBRARY"].to_s.empty?

  # ------------------------------------------------------------------ the whole sequence

  # `DeviceCreated` at creation, the reset pair on a reset, then `DeviceDisposing` and `Disposed` on
  # disposal — XNA's order, every sender the manager, every args `EventArgs.Empty`.
  def test_every_event_fires_in_the_ils_order_with_the_manager_as_sender
    skip "CNA_NATIVE_LIBRARY not supplied" unless native?

    game = EventGame.new
    begin
      game.Run
      assert_equal %i[DeviceCreated DeviceResetting DeviceReset], game.log.map(&:first)
    ensure
      game.Dispose
    end
    assert_equal %i[DeviceCreated DeviceResetting DeviceReset DeviceDisposing Disposed],
                 game.log.map(&:first)
    game.log.each do |name, from_manager, args|
      assert from_manager, "#{name} must have the manager as its sender"
      assert_same CNA::Runtime::EventArgs::Empty, args, name.to_s
    end
  end

  # `OnDeviceCreated(this, EventArgs.Empty)` is the last statement of `CreateDevice`, so it fires
  # when the manager's device comes into being — before the first frame, and late enough for a
  # consumer who subscribed after `GraphicsDeviceManager.new` to see it.
  def test_device_created_fires_before_the_first_frame
    skip "CNA_NATIVE_LIBRARY not supplied" unless native?

    game = EventGame.new
    assert_empty game.log, "constructing the manager alone creates no native device"
    begin
      game.Run
      assert_equal :DeviceCreated, game.log.first.first
    ensure
      game.Dispose
    end
  end

  # The relay, from the other side: raising the *device's* event is what reaches the manager's.
  def test_the_four_device_events_are_relays_of_the_devices_own
    skip "CNA_NATIVE_LIBRARY not supplied" unless native?

    log = []
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    %i[DeviceDisposing DeviceReset DeviceResetting].each do |name|
      manager.__send__(name).add(->(_s, _a) { log << name })
    end
    device = manager.GraphicsDevice
    device.__send__(:raise_DeviceResetting)
    device.__send__(:raise_DeviceReset)
    # `HandleDeviceLost` is a single `ret`, so this one reaches nothing.
    device.__send__(:raise_DeviceLost)
    device.__send__(:raise_Disposing)
    game.Dispose
    assert_equal %i[DeviceResetting DeviceReset DeviceDisposing], log.first(3)
  end

  # ------------------------------------------------------------------ Dispose(Boolean)

  # `if (!disposing) return;` — the whole body is inside that branch, so `Dispose(false)` does
  # nothing at all, not even raise `Disposed`.
  def test_dispose_false_does_nothing
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    log = []
    manager.Disposed.add(->(_s, _a) { log << :disposed })
    device = manager.GraphicsDevice
    manager.Dispose(false)
    assert_empty log
    refute_nil manager.GraphicsDevice
    refute device.IsDisposed
    game.Dispose
  end

  # `if (device != null) { device.Dispose(); device = null; }` then `Disposed`.
  def test_dispose_true_disposes_the_device_nulls_it_and_raises_disposed
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    log = []
    manager.DeviceDisposing.add(->(_s, _a) { log << :device_disposing })
    manager.Disposed.add(->(_s, _a) { log << :disposed })
    device = manager.GraphicsDevice
    manager.Dispose
    assert device.IsDisposed
    assert_nil manager.GraphicsDevice
    # The device's own `Disposing` is what reaches `DeviceDisposing`, so it must precede `Disposed`.
    assert_equal %i[device_disposing disposed], log
    game.Dispose
  end

  # DEVIATION, recorded: XNA's `Dispose(Boolean)` has **no disposed guard**, so a second call
  # raises `Disposed` again — where `Game.Dispose` guards and raises once. The difference is real
  # and both halves are asserted.
  def test_a_second_dispose_raises_disposed_again_and_disposes_nothing_twice
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    log = []
    manager.DeviceDisposing.add(->(_s, _a) { log << :device_disposing })
    manager.Disposed.add(->(_s, _a) { log << :disposed })
    manager.Dispose
    manager.Dispose
    manager.Dispose
    assert_equal %i[device_disposing disposed disposed disposed], log
    game.Dispose
  end

  # The two steps that are already no-ops here, and for a measured reason rather than an omission.
  def test_the_service_and_window_steps_have_nothing_to_undo
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    service = G.const_get(:IGraphicsDeviceService)
    assert_nil game.Services.GetService(service),
               "the producer audit's finding: this manager is not in the managed container"
    manager.Dispose
    assert_nil game.Services.GetService(service)
    game.Dispose
  end

  # ------------------------------------------------------------------ add/remove are managed

  def test_add_and_remove_are_managed_only
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    calls = []
    handler = manager.DeviceReset.add(->(_s, _a) { calls << :first })
    manager.DeviceReset.add(->(_s, _a) { calls << :second })
    manager.GraphicsDevice.__send__(:raise_DeviceReset)
    manager.DeviceReset.remove(handler)
    manager.GraphicsDevice.__send__(:raise_DeviceReset)
    game.Dispose
    assert_equal %i[first second second], calls
  end

  # A raiser with no subscriber is one null check and nothing else.
  def test_a_raiser_with_no_handler_is_harmless
    game = F::Game.new
    manager = F::GraphicsDeviceManager.new(game)
    RAISERS.each do |name|
      manager.__send__(name, manager, CNA::Runtime::EventArgs::Empty)
    end
    game.Dispose
  end
end
