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
end
