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
end
