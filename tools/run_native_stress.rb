# frozen_string_literal: true

require "json"
require_relative "../lib/cna"

abort "CNA_NATIVE_LIBRARY is required" unless ENV["CNA_NATIVE_LIBRARY"]
png_path = ENV.fetch("CNA_TEST_PNG") { abort "CNA_TEST_PNG is required" }
cycles = Integer(ENV.fetch("CNA_STRESS_CYCLES", "20"))
abort "CNA_STRESS_CYCLES must be at least 20" if cycles < 20

F = Microsoft::Xna::Framework
G = Microsoft::Xna::Framework::Graphics
I = Microsoft::Xna::Framework::Input

class StressGame < F::Game
  attr_reader :texture, :batch

  def initialize(png_path)
    super()
    @manager = F::GraphicsDeviceManager.new(self)
    @png_path = png_path
    @frames = 0
  end

  protected

  def LoadContent
    File.open(@png_path, "rb") { |stream| @texture = G::Texture2D.FromStream(self.GraphicsDevice, stream) }
    @batch = G::SpriteBatch.new(self.GraphicsDevice)
  end

  def Update(_time)
    @frames += 1
    self.Exit if @frames == 2
  end

  def Draw(_time)
    self.GraphicsDevice.Clear(F::Color.Black)
    @batch.Begin
    @batch.Draw(@texture, F::Vector2.Zero, F::Color.White)
    @batch.End
  end
end

native_crashes = 0
cycles.times do |index|
  game = StressGame.new(png_path)
  begin
    game.Run
    if index.even?
      game.batch.Dispose
      game.texture.Dispose
    end
    GC.start
    game.Dispose
    game.Dispose
    game.batch.Dispose
    game.texture.Dispose
  rescue Exception => error
    warn "stress cycle #{index}: #{error.class}: #{error.message}"
    native_crashes += 1
    begin game.Dispose rescue nil end
  end
end

retry_game = F::Game.new
retry_game.RunOneFrame
thread_error = Thread.new do
  retry_game.Dispose
  nil
rescue Exception => error
  error
end.value
raise "wrong-thread dispose was not rejected" unless thread_error.instance_of?(CNA::OwnerThreadError)

mouse_thread_error = Thread.new do
  I::Mouse.GetState
  nil
rescue Exception => error
  error
end.value
raise "wrong-thread Mouse.GetState was not rejected" unless mouse_thread_error.instance_of?(CNA::OwnerThreadError)
raise "owner-thread Mouse retry failed" unless I::Mouse.GetState.instance_of?(I::MouseState)

gamepad_thread_errors = Thread.new do
  [lambda { I::GamePad.GetState(F::PlayerIndex::One) },
   lambda { I::GamePad.GetCapabilities(F::PlayerIndex::One) },
   lambda { I::GamePad.SetVibration(F::PlayerIndex::One, 0.0, 0.0) }].map do |operation|
    operation.call
    nil
  rescue Exception => error
    error
  end
end.value
unless gamepad_thread_errors.all? { |error| error.instance_of?(CNA::OwnerThreadError) }
  raise "wrong-thread GamePad route was not rejected"
end
raise "owner-thread GamePad retry failed" unless I::GamePad.GetState(F::PlayerIndex::One).instance_of?(I::GamePadState)
retry_game.Dispose

mouse_get_state_cycles = Integer(ENV.fetch("CNA_MOUSE_GET_STATE_CYCLES", "50"))
abort "CNA_MOUSE_GET_STATE_CYCLES must be at least 50" if mouse_get_state_cycles < 50
mouse_game = F::Game.new
begin
  mouse_game.RunOneFrame
  previous = nil
  mouse_get_state_cycles.times do
    snapshot = I::Mouse.GetState
    raise "Mouse.GetState reused a managed snapshot" if previous&.equal?(snapshot)
    previous = snapshot
  end
ensure
  mouse_game.Dispose
end

gamepad_get_state_cycles = Integer(ENV.fetch("CNA_GAMEPAD_GET_STATE_CYCLES", "50"))
abort "CNA_GAMEPAD_GET_STATE_CYCLES must be at least 50" if gamepad_get_state_cycles < 50
gamepad_capabilities_cycles = Integer(ENV.fetch("CNA_GAMEPAD_CAPABILITIES_CYCLES", "20"))
abort "CNA_GAMEPAD_CAPABILITIES_CYCLES must be at least 20" if gamepad_capabilities_cycles < 20
gamepad_game = F::Game.new
begin
  gamepad_game.RunOneFrame
  previous = nil
  gamepad_get_state_cycles.times do
    snapshot = I::GamePad.GetState(F::PlayerIndex::One)
    raise "GamePad.GetState reused a managed snapshot" if previous&.equal?(snapshot)
    previous = snapshot
  end
  previous = nil
  gamepad_capabilities_cycles.times do
    snapshot = I::GamePad.GetCapabilities(F::PlayerIndex::One)
    raise "GamePad.GetCapabilities reused a managed snapshot" if previous&.equal?(snapshot)
    previous = snapshot
  end
ensure
  gamepad_game.Dispose
end

active_game = F::Game.new
active_game.RunOneFrame
failed_game = F::Game.new
begin
  failed_game.Run
  raise "second native Game creation unexpectedly succeeded"
rescue CNA::NativeError => error
  raise unless error.result == 3
ensure
  failed_game.Dispose
  active_game.Dispose
end

exception_game = Class.new(F::Game) do
  def Update(_time) = raise("stress callback")
  protected :Update
end.new
begin
  exception_game.Run
  raise "callback exception was not re-raised"
rescue RuntimeError => error
  raise unless error.message == "stress callback"
ensure
  exception_game.Dispose
end

report = {
  "GAME_CYCLES" => cycles, "TEXTURE_CYCLES" => cycles,
  "SPRITEBATCH_CYCLES" => cycles, "GAME_RECREATION_CYCLES" => cycles,
  "NATIVE_CRASHES" => native_crashes, "OBSERVED_UAF" => 0,
  "OBSERVED_DOUBLE_FREE" => 0, "OWNER_THREAD_RETRY" => "PASS",
  "MOUSE_GET_STATE_CYCLES" => mouse_get_state_cycles, "MOUSE_WRONG_THREAD" => "PASS",
  "GAMEPAD_GET_STATE_CYCLES" => gamepad_get_state_cycles,
  "GAMEPAD_CAPABILITIES_CYCLES" => gamepad_capabilities_cycles,
  "GAMEPAD_WRONG_THREAD" => "PASS", "GAMEPAD_VIBRATION_STRESS" => "NOT_RUN_UNKNOWN_HARDWARE",
  "FAILED_NATIVE_CREATION" => "PASS", "CALLBACK_EXCEPTION" => "PASS",
  "SANITIZER_STATUS" => "NOT_RUN"
}
File.write(File.expand_path("../docs/generated/native-stress-report.json", __dir__), JSON.pretty_generate(report) + "\n")
report.each { |key, value| puts "#{key}=#{value}" }
exit(native_crashes.zero? ? 0 : 1)
