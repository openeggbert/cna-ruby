# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class NativeIntegrationTest < Minitest::Test
  F = Microsoft::Xna::Framework
  G = Microsoft::Xna::Framework::Graphics
  I = Microsoft::Xna::Framework::Input

  def setup
    skip "CNA_NATIVE_LIBRARY not supplied" unless ENV["CNA_NATIVE_LIBRARY"]
  end

  class LifecycleGame < F::Game
    attr_reader :events, :updates, :draws

    def initialize(frame_limit = 3)
      super()
      @events = []
      @updates = 0
      @draws = 0
      @frame_limit = frame_limit
    end

    protected

    def Initialize = @events << :initialize
    def LoadContent = @events << :load
    def BeginRun = @events << :begin_run
    def Update(_time)
      @events << :update
      @updates += 1
      self.Exit if @updates == @frame_limit
    end
    def Draw(_time)
      @events << :draw
      @draws += 1
    end
    def EndRun = @events << :end_run
    def UnloadContent = @events << :unload
  end

  def test_native_lifecycle_and_double_dispose
    game = LifecycleGame.new
    begin
      game.Run
    ensure
      game.Dispose
      game.Dispose
    end
    assert_equal 3, game.updates
    assert_equal 2, game.draws
    assert_equal %i[initialize load begin_run update draw update draw update end_run unload], game.events
  end

  # A Game that owns a GraphicsDeviceManager. The manager is what makes disposal ordering
  # observable: Game#Dispose releases it before it destroys the host, and destroying the host
  # delivers one last unload_content callback afterwards.
  class ManagedLifecycleGame < LifecycleGame
    def initialize(frame_limit = 3)
      super
      @manager = F::GraphicsDeviceManager.new(self)
    end

    attr_reader :manager
  end

  # Regression: disposing a Game that owns a manager and has actually run raised
  # CNA::DisposedObjectError. Game#Dispose releases the manager first -- correctly, because
  # cna_graphics_device_manager_create documents "release it before the game" -- and cna_game_destroy
  # then delivers unload_content, whose callback prologue borrowed the manager's device through the
  # handle that had just been released. A disposed manager now attaches no device, which is the same
  # answer it already gave when CNA reports CNA_RESULT_INVALID_STATE for "no device exists".
  def test_disposing_a_game_that_owns_a_manager_after_running_is_clean
    game = ManagedLifecycleGame.new
    begin
      game.RunOneFrame
    ensure
      game.Dispose
      game.Dispose
    end
    assert_includes game.events, :unload, "the last unload_content must still be delivered"
    # RunOneFrame delivers no begin_run, matching XNA's RunGame(false).
    assert_equal %i[initialize load update draw unload], game.events
    # The manager's own device wrapper survives disposal as an object and reports itself disposed
    # rather than raising, and it never resurrects a borrowed handle.
    assert game.manager.GraphicsDevice.IsDisposed
    assert_equal 0, game.manager.GraphicsDevice.instance_variable_get(:@callback_handle)
  end

  # The same path under a full blocking Run, which delivers end_run before the destroy-time unload.
  def test_disposing_a_managed_game_after_a_full_run_is_clean
    game = ManagedLifecycleGame.new
    begin
      game.Run
    ensure
      game.Dispose
    end
    assert_equal %i[initialize load begin_run update draw update draw update end_run unload],
                 game.events
    assert_equal 3, game.updates
    assert_equal 2, game.draws
  end

  # ------------------------------------------------------- Foundation 41, the native Game events

  # A Game that records every lifecycle callback and every Game event in one ordered log, so the
  # interleaving is measured rather than inferred.
  class EventOrderGame < F::Game
    attr_reader :log

    def initialize(frame_limit)
      super()
      @log = []
      @updates = 0
      @frame_limit = frame_limit
      self.Activated.add(->(sender, args) { @log << [:Activated, sender.equal?(self), args] })
      self.Deactivated.add(->(sender, args) { @log << [:Deactivated, sender.equal?(self), args] })
      self.Exiting.add(->(sender, args) { @log << [:Exiting, sender.nil?, args] })
      self.Disposed.add(->(sender, args) { @log << [:Disposed, sender.equal?(self), args] })
    end

    def names = @log.map { |entry| entry.is_a?(Array) ? entry.first : entry }

    protected

    def Initialize = @log << :initialize
    def LoadContent = @log << :load_content
    def BeginRun = @log << :begin_run
    def Update(_time)
      @log << :update
      @updates += 1
      self.Exit if @frame_limit && @updates == @frame_limit
    end
    def Draw(_time) = @log << :draw
    def EndRun = @log << :end_run
    def UnloadContent = @log << :unload_content
  end

  # Activated arrives after BeginRun and before the first Update; Exiting after the Update that
  # requested the exit and before EndRun; Disposed at disposal. Every sender and args is checked.
  def test_game_events_are_really_raised_in_the_measured_order
    game = EventOrderGame.new(2)
    begin
      game.Run
    ensure
      game.Dispose
    end
    assert_equal %i[initialize load_content begin_run Activated update draw update
                    Exiting end_run unload_content Disposed], game.names
    game.log.grep(Array).each do |identity, sender_ok, args|
      assert sender_ok, "#{identity} sender"
      assert_same CNA::Runtime::EventArgs::Empty, args, "#{identity} args"
    end
    # Exactly once each, and HEADLESS produced no deactivation, which is not fabricated.
    assert_equal 1, game.names.count(:Activated)
    assert_equal 1, game.names.count(:Exiting)
    assert_equal 1, game.names.count(:Disposed)
    assert_equal 0, game.names.count(:Deactivated)
  end

  # RunOneFrame never exits its loop, so XNA would raise no Exiting -- and neither does this. The
  # already-bound CNA_GameCallbacks::exiting slot fires here, which is exactly why it is not the
  # source this projection uses.
  def test_run_one_frame_raises_no_exiting_and_no_activation
    game = EventOrderGame.new(nil)
    begin
      game.RunOneFrame
    ensure
      game.Dispose
    end
    assert_equal %i[initialize load_content update draw unload_content Disposed], game.names
  end

  # The registrations are released before the game is destroyed, and releasing them is what stops
  # CNA calling back into a Ruby closure afterwards.
  def test_event_registrations_are_released_before_the_game_is_destroyed
    game = EventOrderGame.new(1)
    host = game.__send__(:ensure_host)
    registrations = host.instance_variable_get(:@event_registrations)
    assert_equal 3, registrations.length, "Activated, Deactivated and Exiting; Disposed is managed"
    assert(registrations.none?(&:zero?))
    begin
      game.Run
    ensure
      game.Dispose
    end
    assert_empty host.instance_variable_get(:@event_registrations)
    assert_equal 1, game.names.count(:Disposed)
  end

  # A handler that raises inside a native event callback must not escape into C. It is captured the
  # way a lifecycle callback's exception is and surfaces from the enclosing native call.
  def test_an_exception_from_a_game_event_handler_crosses_the_boundary_safely
    game = EventOrderGame.new(2)
    game.Activated.add(->(_sender, _args) { raise "from an Activated handler" })
    begin
      error = assert_raises(RuntimeError) { game.Run }
      assert_equal "from an Activated handler", error.message
    ensure
      game.Dispose
    end
  end

  %w[Initialize LoadContent Update Draw].each do |callback|
    define_method("test_#{callback.downcase}_exception_is_contained") do
      callback_name = callback
      game_class = Class.new(F::Game) do
        define_method(callback_name) { |_time = nil| raise "contained #{callback_name}" }
        protected callback_name
      end
      game = game_class.new
      begin
        error = assert_raises(RuntimeError) { game.Run }
        assert_equal "contained #{callback_name}", error.message
      ensure
        game.Dispose
      end
    end
  end

  class GraphicsGame < F::Game
    attr_reader :dimensions, :pressed, :updates, :draws

    def initialize(png_path, frame_limit)
      super()
      @manager = F::GraphicsDeviceManager.new(self)
      @png_path = png_path
      @frame_limit = frame_limit
      @updates = 0
      @draws = 0
    end

    protected

    def LoadContent
      File.open(@png_path, "rb") { |stream| @texture = G::Texture2D.FromStream(self.GraphicsDevice, stream) }
      @batch = G::SpriteBatch.new(self.GraphicsDevice)
      @dimensions = [@texture.Width, @texture.Height]
    end

    def Update(_time)
      @pressed = I::Keyboard.GetState.GetPressedKeys
      @updates += 1
      self.Exit if @updates == @frame_limit
    end

    def Draw(_time)
      self.GraphicsDevice.Clear(F::Color.Black)
      @batch.Begin
      @batch.Draw(@texture, F::Vector2.new(16, 24), nil, F::Color.White, 0.25,
                  F::Vector2.Zero, F::Vector2.new(0.75), G::SpriteEffects::None, 0.0)
      @batch.End
      @draws += 1
    end

    def UnloadContent
      @batch.Dispose
      @batch.Dispose
      @texture.Dispose
      @texture.Dispose
    end
  end

  def test_real_png_clear_sprite_and_keyboard
    png = ENV["CNA_TEST_PNG"]
    skip "CNA_TEST_PNG not supplied" unless png
    game = GraphicsGame.new(png, 3)
    begin
      game.Run
    ensure
      game.Dispose
    end
    assert_equal [128, 128], game.dimensions
    assert_instance_of Array, game.pressed
    assert_equal 3, game.updates
    assert_equal 2, game.draws
  end

  def test_real_mouse_snapshot_position_and_window_handle_routes
    game = F::Game.new
    begin
      game.RunOneFrame
      first = I::Mouse.GetState
      second = I::Mouse.GetState
      assert_instance_of I::MouseState, first
      assert_instance_of I::MouseState, second
      refute_same first, second
      [first.LeftButton, first.MiddleButton, first.RightButton,
       first.XButton1, first.XButton2].each { |button| assert_instance_of I::ButtonState, button }
      assert [first.X, first.Y, first.ScrollWheelValue].all? { |value| value.instance_of?(Integer) }

      # HEADLESS may be unable to move a physical cursor. This proves only that the canonical CNA
      # window-relative operation executes successfully; no synthetic round trip is asserted.
      assert_nil I::Mouse.SetPosition(0, 0)
      handle = I::Mouse.WindowHandle
      assert_instance_of Integer, handle
      assert_nil I::Mouse.__send__(:"WindowHandle=", handle)
      assert_equal handle, I::Mouse.WindowHandle
    ensure
      game.Dispose
    end
  end

  class MouseCallbackGame < F::Game
    attr_reader :mouse_state, :window_handle

    protected

    def Update(_time)
      @mouse_state = I::Mouse.GetState
      @window_handle = I::Mouse.WindowHandle
      I::Mouse.SetPosition(0, 0)
      I::Mouse.__send__(:"WindowHandle=", @window_handle)
    end
  end

  def test_mouse_routes_work_during_native_callback
    game = MouseCallbackGame.new
    begin
      game.RunOneFrame
      assert_instance_of I::MouseState, game.mouse_state
      assert_instance_of Integer, game.window_handle
    ensure
      game.Dispose
    end
  end

  def test_mouse_owner_thread_shutdown_and_generation_reselection
    uninitialized = F::Game.new
    assert_raises(CNA::InvalidBindingStateError) { I::Mouse.GetState }
    uninitialized.Dispose

    first_game = F::Game.new
    first_game.RunOneFrame
    handle = I::Mouse.WindowHandle
    errors = Thread.new do
      [lambda { I::Mouse.GetState }, lambda { I::Mouse.SetPosition(0, 0) },
       lambda { I::Mouse.WindowHandle }, lambda { I::Mouse.__send__(:"WindowHandle=", handle) }].map do |operation|
        operation.call
        nil
      rescue Exception => error
        error
      end
    end.value
    assert errors.all? { |error| error.instance_of?(CNA::OwnerThreadError) }
    assert_instance_of I::MouseState, I::Mouse.GetState
    first_game.Dispose
    assert_raises(CNA::InvalidBindingStateError) { I::Mouse.GetState }

    second_game = F::Game.new
    begin
      second_game.RunOneFrame
      assert_instance_of I::MouseState, I::Mouse.GetState
    ensure
      second_game.Dispose
    end
  ensure
    first_game&.Dispose
    uninitialized&.Dispose
  end

  def test_mouse_native_failures_cross_the_central_error_boundary
    library = CNA::Native.library
    state = CNA::Native::Layouts::MouseState.new
    window = library.pointer_for("Q", 0)
    assert_raises(CNA::NativeError) { library.call("cna_mouse_get_state", 0, state.pointer) }
    assert_raises(CNA::NativeError) { library.call("cna_mouse_set_position", 0, 0, 0) }
    assert_raises(CNA::NativeError) { library.call("cna_mouse_get_window_handle", 0, window) }
    assert_raises(CNA::NativeError) { library.call("cna_mouse_set_window_handle", 0, 0) }
  end

  def test_real_gamepad_state_dead_zones_capabilities_and_safe_vibration_routes
    game = F::Game.new
    begin
      game.RunOneFrame
      players = [F::PlayerIndex::One, F::PlayerIndex::Two,
                 F::PlayerIndex::Three, F::PlayerIndex::Four]
      players.each do |player|
        default = I::GamePad.GetState(player)
        independent = I::GamePad.GetState(player, I::GamePadDeadZone::IndependentAxes)
        none = I::GamePad.GetState(player, I::GamePadDeadZone::None)
        circular = I::GamePad.GetState(player, I::GamePadDeadZone::Circular)
        [default, independent, none, circular].each do |state|
          assert_instance_of I::GamePadState, state
          assert_instance_of Integer, state.PacketNumber
          assert_includes [true, false], state.IsConnected
          assert_includes(-1.0..1.0, state.ThumbSticks.Left.X)
          assert_includes(-1.0..1.0, state.ThumbSticks.Left.Y)
          assert_includes(-1.0..1.0, state.ThumbSticks.Right.X)
          assert_includes(-1.0..1.0, state.ThumbSticks.Right.Y)
          assert_includes(0.0..1.0, state.Triggers.Left)
          assert_includes(0.0..1.0, state.Triggers.Right)
        end
        refute_same default, I::GamePad.GetState(player)

        capabilities = I::GamePad.GetCapabilities(player)
        assert_instance_of I::GamePadCapabilities, capabilities
        assert_equal default.IsConnected, capabilities.IsConnected
        assert_instance_of I::GamePadType, capabilities.GamePadType
        %i[
          IsConnected HasAButton HasBackButton HasBButton HasDPadDownButton HasDPadLeftButton
          HasDPadRightButton HasDPadUpButton HasLeftShoulderButton HasLeftStickButton
          HasRightShoulderButton HasRightStickButton HasStartButton HasXButton HasYButton
          HasBigButton HasLeftXThumbStick HasLeftYThumbStick HasRightXThumbStick
          HasRightYThumbStick HasLeftTrigger HasRightTrigger HasLeftVibrationMotor
          HasRightVibrationMotor HasVoiceSupport
        ].each { |property| assert_includes [true, false], capabilities.public_send(property) }
      end

      # A single all-off request exercises the real actuator route without producing rumble on
      # unknown hardware. The Boolean is the CNA/backend answer and is deliberately not forced.
      assert_includes [true, false], I::GamePad.SetVibration(F::PlayerIndex::One, 0.0, 0.0)
    ensure
      game.Dispose
    end
  end

  class GamePadCallbackGame < F::Game
    attr_reader :state, :capabilities, :vibration_applied

    protected

    def Update(_time)
      @state = I::GamePad.GetState(F::PlayerIndex::One)
      @capabilities = I::GamePad.GetCapabilities(F::PlayerIndex::One)
      @vibration_applied = I::GamePad.SetVibration(F::PlayerIndex::One, 0.0, 0.0)
    end
  end

  def test_gamepad_routes_work_during_native_callback
    game = GamePadCallbackGame.new
    begin
      game.RunOneFrame
      assert_instance_of I::GamePadState, game.state
      assert_instance_of I::GamePadCapabilities, game.capabilities
      assert_includes [true, false], game.vibration_applied
    ensure
      game.Dispose
    end
  end

  def test_gamepad_owner_thread_shutdown_ambiguity_and_generation_reselection
    first_uninitialized = F::Game.new
    second_uninitialized = F::Game.new
    assert_raises(CNA::InvalidBindingStateError) { I::GamePad.GetState(F::PlayerIndex::One) }
    second_uninitialized.Dispose
    assert_raises(CNA::InvalidBindingStateError) { I::GamePad.GetCapabilities(F::PlayerIndex::One) }
    first_uninitialized.Dispose

    first_game = F::Game.new
    first_game.RunOneFrame
    errors = Thread.new do
      [lambda { I::GamePad.GetState(F::PlayerIndex::One) },
       lambda { I::GamePad.GetCapabilities(F::PlayerIndex::One) },
       lambda { I::GamePad.SetVibration(F::PlayerIndex::One, 0.0, 0.0) }].map do |operation|
        operation.call
        nil
      rescue Exception => error
        error
      end
    end.value
    assert errors.all? { |error| error.instance_of?(CNA::OwnerThreadError) }
    assert_instance_of I::GamePadState, I::GamePad.GetState(F::PlayerIndex::One)
    first_game.Dispose
    assert_raises(CNA::InvalidBindingStateError) { I::GamePad.GetState(F::PlayerIndex::One) }

    second_game = F::Game.new
    begin
      second_game.RunOneFrame
      assert_instance_of I::GamePadState, I::GamePad.GetState(F::PlayerIndex::One)
      assert_instance_of I::GamePadCapabilities, I::GamePad.GetCapabilities(F::PlayerIndex::One)
    ensure
      second_game.Dispose
    end
  ensure
    second_game&.Dispose
    first_game&.Dispose
    second_uninitialized&.Dispose
    first_uninitialized&.Dispose
  end

  def test_gamepad_native_failures_cross_the_central_error_boundary
    library = CNA::Native.library
    state = CNA::Native::Layouts::GamePadState.new
    capabilities = CNA::Native::Layouts::GamePadCapabilities.new
    applied = library.pointer_for("C", 0)
    assert_raises(CNA::NativeError) do
      library.call("cna_gamepad_get_state", 0, 0, state.pointer)
    end
    assert_raises(CNA::NativeError) do
      library.call("cna_gamepad_get_state_with_dead_zone", 0, 0, 1, state.pointer)
    end
    assert_raises(CNA::NativeError) do
      library.call("cna_gamepad_get_capabilities", 0, 0, capabilities.pointer)
    end
    assert_raises(CNA::NativeError) do
      library.call("cna_gamepad_set_vibration", 0, 0, 0.0, 0.0, applied)
    end
  end
end
