# frozen_string_literal: true

require "minitest/autorun"
require "fiddle"
require "json"
require "pathname"
require_relative "reviewed_measurements"
require_relative "renderer_environment"
require_relative "../lib/cna"

# `GraphicsDevice`'s six events — and the two questions that decided how each is raised.
#
# **Which of them can CNA deliver?** Three: `DeviceLost`, `DeviceReset` and `DeviceResetting`, over
# `cna_graphics_device_subscribe_event`. `Disposing` is the fourth identity that route carries and
# it cannot reach a managed handler at all: CNA raises it inside `cna_game_destroy`, by which point
# the graphics device manager handle — and every registration made through the device — has already
# been released, because the ABI documents "release it before the game". Measured both ways below.
#
# **What can CNA's payload carry?** For the two resource events, presence only. CNA's own header
# says why: "the canonical event is raised from the graphics-resource base constructor, so the
# reported object is still under construction … no native object pointer crosses the ABI."
# `ResourceCreatedEventArgs.Resource` *is* that object, and `ResourceDestroyedEventArgs` carries
# `Name` and `Tag`, which are managed properties CNA never sees. This projection has all three,
# because the resource is a Ruby object it constructed — so both are raised managed from
# `GraphicsResource`, which is exactly where `DeviceResourceManager.AddTrackedObject` and
# `ReleaseAllReferences` raise them in XNA.
class GraphicsDeviceEventsTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  ROOT = Pathname(__dir__).join("..").expand_path
  STRICT = JSON.parse(ROOT.join("docs", "generated", "api-compat-report.json").read).freeze
  NAME = "Microsoft.Xna.Framework.Graphics.GraphicsDevice"
  EVENTS = %i[Disposing DeviceLost DeviceReset DeviceResetting ResourceCreated ResourceDestroyed].freeze

  def test_the_six_left_the_partial_remainder
    EVENTS.each do |member|
      refute_includes ReviewedScoreboard.partial_remainder(STRICT, NAME).join(" "), "::#{member} ", member.to_s
    end
    assert_equal ReviewedScoreboard::GRAPHICS_DEVICE_OUTSTANDING,
                 ReviewedScoreboard.outstanding(STRICT, NAME)
    assert_equal ReviewedScoreboard::EVENT_IDENTITIES, STRICT.fetch("EVENT_IDENTITIES")
    assert_equal 0, STRICT.fetch("EVENT_MAPPING_MISMATCH")
  end

  # One reader identity each, never an add_/remove_ pair and never a writer — the rule every
  # projected event in this binding follows.
  def test_each_event_is_one_reader_returning_the_support_type
    device_events = STRICT.fetch("eventIdentities").grep(/^#{Regexp.escape(NAME)}::/)
    assert_equal EVENTS.map { |name| "#{NAME}::#{name}" }.sort, device_events.sort
    EVENTS.each do |name|
      assert G::GraphicsDevice.public_method_defined?(name), name.to_s
      refute G::GraphicsDevice.method_defined?(:"#{name}="), "#{name}="
      refute G::GraphicsDevice.method_defined?(:"add_#{name}"), "add_#{name}"
      refute G::GraphicsDevice.method_defined?(:"raise_#{name}"),
             "raise_#{name} must stay private, as XNA's is"
    end
  end

  # Three subscriptions, not four, and the two resource routes are deliberately unbound.
  def test_only_the_deliverable_identities_are_bound
    symbols = CNA::Native::Manifest::FUNCTIONS.map(&:symbol)
    assert_includes symbols, "cna_graphics_device_subscribe_event"
    assert_includes symbols, "cna_graphics_device_unsubscribe"
    refute_includes symbols, "cna_graphics_device_subscribe_resource_created"
    refute_includes symbols, "cna_graphics_device_subscribe_resource_destroyed"
    constants = CNA::Native::Manifest::CONSTANTS.keys.grep(/\ACNA_GRAPHICS_DEVICE_EVENT_/)
    assert_equal %w[CNA_GRAPHICS_DEVICE_EVENT_DEVICE_LOST CNA_GRAPHICS_DEVICE_EVENT_DEVICE_RESET
                    CNA_GRAPHICS_DEVICE_EVENT_DEVICE_RESETTING].sort, constants.sort
  end

  class EventGame < F::Game
    attr_reader :result

    def initialize(&body)
      @body = body
      super()
      F::GraphicsDeviceManager.new(self)
    end

    def Draw(_time)
      @result = @body.call(self.GraphicsDevice)
    ensure
      self.Exit
    end
  end

  def with_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = EventGame.new { |device| yield device }
    begin
      game.Run
      game.result
    ensure
      game.Dispose
    end
  end

  # ------------------------------------------------------------------ the reset pair

  # CNA's header says a successful reset "raises the device's resetting and reset events in that
  # order", and this is that order arriving at managed handlers.
  def test_a_reset_raises_resetting_then_reset_with_the_device_as_sender
    log = with_device do |device|
      entries = []
      device.DeviceResetting.add(->(sender, args) { entries << [:resetting, sender.equal?(device), args] })
      device.DeviceReset.add(->(sender, args) { entries << [:reset, sender.equal?(device), args] })
      device.Reset
      entries
    end
    assert_equal 2, log.length
    assert_equal [:resetting, true], log.fetch(0).first(2)
    assert_equal [:reset, true], log.fetch(1).first(2)
    log.each { |entry| assert_same CNA::Runtime::EventArgs::Empty, entry.fetch(2) }
  end

  def test_a_resizing_reset_raises_the_same_pair
    log = with_device do |device|
      entries = []
      device.DeviceResetting.add(->(_s, _a) { entries << :resetting })
      device.DeviceReset.add(->(_s, _a) { entries << :reset })
      parameters = device.PresentationParameters.Clone
      parameters.BackBufferWidth = 256
      parameters.BackBufferHeight = 128
      device.Reset(parameters)
      entries
    end
    assert_equal %i[resetting reset], log
  end

  # A handler's exception has nowhere to travel back through the `void` callback, so it is captured
  # and re-raised by the Ruby frame that provoked it — which for a reset is `Reset` itself, exactly
  # where XNA's would propagate from.
  def test_a_handler_exception_propagates_out_of_reset
    outcome = with_device do |device|
      device.DeviceResetting.add(->(_s, _a) { raise "handler said no" })
      begin
        device.Reset
        :ok
      rescue StandardError => error
        [error.class, error.message]
      end
    end
    assert_equal [RuntimeError, "handler said no"], outcome
  end

  # ------------------------------------------------------------------ Disposing

  # Raised managed, from the device's own invalidation, because the native signal cannot arrive in
  # time. The two halves of that measurement are the next test.
  def test_disposing_is_raised_once_with_the_device_as_sender
    log = []
    game = F::Game.new
    F::GraphicsDeviceManager.new(game)
    device = game.GraphicsDevice
    device.Disposing.add(->(sender, args) { log << [sender.equal?(device), args] })
    game.Dispose
    game.Dispose
    assert_equal 1, log.length, "invalidation returns early on a second call, so the event is raised once"
    assert_equal true, log.fetch(0).fetch(0)
    assert_same CNA::Runtime::EventArgs::Empty, log.fetch(0).fetch(1)
    assert device.IsDisposed
  end

  def test_disposing_reaches_a_handler_on_a_game_that_ran
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    log = []
    game = EventGame.new { |device| device.Disposing.add(->(_s, _a) { log << :disposing }) }
    game.Run
    assert_empty log, "running does not dispose"
    game.Dispose
    assert_equal [:disposing], log
  end

  # **The measurement that decided it.** A *leaked* native subscription — one this test makes by
  # hand and never releases — does receive CNA's `CNA_GRAPHICS_DEVICE_EVENT_DISPOSING`, and it
  # arrives during `Game#Dispose`, after the manager handle every correctly released registration
  # belongs to is already gone. So the identity exists, CNA raises it, and no released subscription
  # can be alive to hear it.
  def test_cna_raises_its_own_disposing_only_after_every_registration_is_released
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    log = []
    keepalive = []
    game = EventGame.new do |device|
      handle = CNA::Native.library.instance_variable_get(:@handle)
      subscribe = Fiddle::Function.new(handle["cna_graphics_device_subscribe_event"],
                                       [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_VOIDP,
                                        Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT32_T)
      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID,
                                                  [Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP]) do |_d, _c|
        log << :native_disposing
        nil
      end
      keepalive << callback
      output = CNA::Native.library.pointer_for("Q", 0)
      # `CNA_GRAPHICS_DEVICE_EVENT_DISPOSING` is zero, and it is deliberately absent from the
      # manifest's constants, so the identity is written out here rather than looked up.
      subscribe.call(device.__send__(:native_handle), 0, callback, 0, output)
      device.Disposing.add(->(_s, _a) { log << :managed_disposing })
    end
    game.Run
    assert_empty log
    game.Dispose
    assert_equal %i[managed_disposing native_disposing], log,
                 "the managed raise is the device's own invalidation; CNA's arrives later, " \
                 "after the manager that owns every registration is already released"
  end

  # ------------------------------------------------------------------ the two resource events

  def test_creating_a_resource_raises_resource_created_with_the_resource
    outcome = with_device do |device|
      seen = []
      device.ResourceCreated.add(->(sender, args) { seen << [sender.equal?(device), args.Resource] })
      texture = G::Texture2D.new(device, 4, 4)
      begin
        [seen.length, seen.fetch(0).fetch(0), seen.fetch(0).fetch(1).equal?(texture)]
      ensure
        texture.Dispose
      end
    end
    assert_equal [1, true, true], outcome
  end

  # `FireCreatedEvent` keeps **one** args object per device, writes the new resource into it, and
  # **nulls that field once the handlers return**. Both are XNA's, and both are observable.
  def test_the_created_args_are_reused_and_cleared_after_dispatch
    outcome = with_device do |device|
      stash = []
      during = []
      device.ResourceCreated.add(->(_s, args) { stash << args; during << args.Resource })
      first = G::Texture2D.new(device, 4, 4)
      second = G::Texture2D.new(device, 2, 2)
      begin
        [stash.fetch(0).equal?(stash.fetch(1)),
         during.fetch(0).equal?(first) && during.fetch(1).equal?(second),
         stash.fetch(0).Resource, stash.length]
      ensure
        first.Dispose
        second.Dispose
      end
    end
    assert outcome.fetch(0), "one args object per device, reused"
    assert outcome.fetch(1), "and the handler sees the resource while it is dispatching"
    assert_nil outcome.fetch(2), "but the field is cleared once the handlers return"
    assert_equal 2, outcome.fetch(3)
  end

  def test_disposing_a_resource_raises_resource_destroyed_with_its_name_and_tag
    outcome = with_device do |device|
      seen = []
      device.ResourceDestroyed.add(->(sender, args) { seen << [sender.equal?(device), args.Name, args.Tag] })
      texture = G::Texture2D.new(device, 4, 4)
      texture.Name = "atlas"
      texture.Tag = 42
      texture.Dispose
      seen
    end
    assert_equal [[true, "atlas", 42]], outcome
  end

  # The destroyed args are reused too — and, unlike the created ones, **not** cleared afterwards:
  # `FireDestroyedEvent`'s IL ends at `ret` immediately after `Invoke`.
  def test_the_destroyed_args_are_reused_and_not_cleared
    outcome = with_device do |device|
      stash = []
      device.ResourceDestroyed.add(->(_s, args) { stash << args })
      first = G::Texture2D.new(device, 4, 4)
      first.Name = "first"
      first.Dispose
      after_first = [stash.fetch(0).Name, stash.fetch(0).Tag]
      second = G::Texture2D.new(device, 2, 2)
      second.Dispose
      [stash.fetch(0).equal?(stash.fetch(1)), after_first, [stash.fetch(0).Name, stash.fetch(0).Tag]]
    end
    assert outcome.fetch(0), "one args object per device, reused"
    assert_equal ["first", nil], outcome.fetch(1), "and still readable after dispatch"
    assert_equal [nil, nil], outcome.fetch(2), "the next raise overwrites both fields"
  end

  # XNA's state objects call `Object::.ctor()` and never reach `AddTrackedObject`, so they are not
  # tracked resources and raise neither event. Their `GraphicsDevice` is null, which is what says so.
  def test_a_state_object_raises_neither_resource_event
    outcome = with_device do |device|
      seen = []
      device.ResourceCreated.add(->(_s, _a) { seen << :created })
      device.ResourceDestroyed.add(->(_s, _a) { seen << :destroyed })
      state = G::BlendState.new
      device_of_state = state.GraphicsDevice
      state.Dispose
      [seen, device_of_state]
    end
    assert_empty outcome.fetch(0)
    assert_nil outcome.fetch(1)
  end

  # The resource's own `Disposing` and the device's `ResourceDestroyed` are two different events and
  # they arrive in the order XNA's release performs them: the native release raises the device's
  # first, and `~GraphicsResource()` raises the resource's after.
  def test_the_device_event_precedes_the_resource_s_own
    order = with_device do |device|
      entries = []
      device.ResourceDestroyed.add(->(_s, _a) { entries << :device_resource_destroyed })
      texture = G::Texture2D.new(device, 4, 4)
      texture.Disposing.add(->(_s, _a) { entries << :resource_disposing })
      texture.Dispose
      entries
    end
    assert_equal %i[device_resource_destroyed resource_disposing], order
  end

  # Every kind of graphics resource this binding builds is a tracked one, so every kind raises the
  # pair. Nothing here is special-cased to `Texture2D`.
  def test_every_tracked_resource_kind_raises_the_pair
    counts = with_device do |device|
      created = []
      destroyed = []
      device.ResourceCreated.add(->(_s, args) { created << args.Resource.class.name.split("::").last })
      device.ResourceDestroyed.add(->(_s, _a) { destroyed << :one })
      resources = [
        G::Texture2D.new(device, 4, 4),
        G::VertexBuffer.new(device, G::VertexPositionColor, 3, G::BufferUsage::None),
        G::IndexBuffer.new(device, G::IndexElementSize::SixteenBits, 3, G::BufferUsage::None),
        G::RenderTarget2D.new(device, 8, 8),
        G::OcclusionQuery.new(device)
      ]
      resources.each(&:Dispose)
      [created, destroyed.length]
    end
    assert_equal %w[Texture2D VertexBuffer IndexBuffer RenderTarget2D OcclusionQuery], counts.fetch(0)
    assert_equal 5, counts.fetch(1)
  end

  # ------------------------------------------------------------------ registration lifetime

  # The header says a registration "keeps the game alive in the same way an owned graphics resource
  # does", so a leaked one would hold the game open. Every subscription is released by the device's
  # invalidation, and this measures that the release happened rather than that it was intended.
  def test_every_native_registration_is_released_with_the_device
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    game = EventGame.new { |device| device.__send__(:instance_variable_get, :@event_registrations) }
    game.Run
    registrations = game.result
    assert_equal 3, registrations.length, "one per deliverable identity"
    refute_includes registrations, 0
    game.Dispose
    device = game.GraphicsDevice
    assert_empty device.__send__(:instance_variable_get, :@event_registrations)
    # A second release is `CNA_RESULT_INVALID_HANDLE`, which is what proves the first one happened.
    handle = CNA::Native.library.instance_variable_get(:@handle)
    unsubscribe = Fiddle::Function.new(handle["cna_graphics_device_unsubscribe"],
                                       [Fiddle::TYPE_UINT64_T], Fiddle::TYPE_UINT32_T)
    registrations.each { |registration| refute_equal 0, unsubscribe.call(registration) }
  end

  # Subscribing happens once, at the first callback with a live handle, and not again on every
  # frame — the "earliest reachable moment" argument `ensure_initial_device_state` records.
  def test_the_subscription_is_made_once
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]

    seen = []
    game = Class.new(F::Game) do
      attr_reader :frames

      def initialize(seen)
        @seen = seen
        @frames = 0
        super()
        F::GraphicsDeviceManager.new(self)
      end

      def Draw(_time)
        @frames += 1
        @seen << self.GraphicsDevice.__send__(:instance_variable_get, :@event_registrations).dup
      ensure
        self.Exit if @frames >= 2
      end
    end.new(seen)
    begin
      game.Run
    ensure
      game.Dispose
    end
    assert_operator seen.length, :>=, 1
    assert_equal 1, seen.uniq.length, "the same three registrations every frame"
  end

  # An event a consumer never subscribes to still costs one native registration and nothing else:
  # `add`/`remove` are pure managed, exactly as a CLR multicast delegate is.
  def test_add_and_remove_are_managed_only
    outcome = with_device do |device|
      calls = []
      handler = device.DeviceReset.add(->(_s, _a) { calls << :first })
      device.DeviceReset.add(->(_s, _a) { calls << :second })
      device.Reset
      device.DeviceReset.remove(handler)
      device.Reset
      calls
    end
    assert_equal %i[first second second], outcome
  end
end
