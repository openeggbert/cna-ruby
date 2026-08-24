# frozen_string_literal: true

require "digest"
require "json"
require_relative "../lib/cna"

abort "CNA_NATIVE_LIBRARY is required" unless ENV["CNA_NATIVE_LIBRARY"]

F = Microsoft::Xna::Framework
I = F::Input

def vector(value) = {"x" => value.X, "y" => value.Y}

def state_record(state)
  {
    "cnaResult" => "CNA_RESULT_SUCCESS",
    "isConnected" => state.IsConnected,
    "packetNumber" => state.PacketNumber,
    "pressed" => %i[
      DPadUp DPadDown DPadLeft DPadRight Start Back LeftStick RightStick
      LeftShoulder RightShoulder BigButton A B X Y LeftThumbstickLeft
      LeftThumbstickRight LeftThumbstickDown LeftThumbstickUp RightThumbstickLeft
      RightThumbstickRight RightThumbstickDown RightThumbstickUp LeftTrigger RightTrigger
    ].select { |name| state.IsButtonDown(I::Buttons.const_get(name)) }.map(&:to_s),
    "leftThumbStick" => vector(state.ThumbSticks.Left),
    "rightThumbStick" => vector(state.ThumbSticks.Right),
    "leftTrigger" => state.Triggers.Left,
    "rightTrigger" => state.Triggers.Right
  }
end

def capabilities_record(capabilities)
  properties = %i[
    IsConnected HasAButton HasBackButton HasBButton HasDPadDownButton HasDPadLeftButton
    HasDPadRightButton HasDPadUpButton HasLeftShoulderButton HasLeftStickButton
    HasRightShoulderButton HasRightStickButton HasStartButton HasXButton HasYButton
    HasBigButton HasLeftXThumbStick HasLeftYThumbStick HasRightXThumbStick
    HasRightYThumbStick HasLeftTrigger HasRightTrigger HasLeftVibrationMotor
    HasRightVibrationMotor HasVoiceSupport
  ]
  {"cnaResult" => "CNA_RESULT_SUCCESS", "gamePadType" => capabilities.GamePadType.to_s}
    .merge(properties.to_h { |name| [name.to_s, capabilities.public_send(name)] })
end

game = F::Game.new
players = [F::PlayerIndex::One, F::PlayerIndex::Two, F::PlayerIndex::Three, F::PlayerIndex::Four]
records = []
vibration = nil
begin
  game.RunOneFrame
  players.each do |player|
    records << {
      "playerIndex" => player.to_s,
      "nativeSlot" => player.to_i,
      "defaultIndependentAxes" => state_record(I::GamePad.GetState(player)),
      "none" => state_record(I::GamePad.GetState(player, I::GamePadDeadZone::None)),
      "independentAxes" => state_record(I::GamePad.GetState(player, I::GamePadDeadZone::IndependentAxes)),
      "circular" => state_record(I::GamePad.GetState(player, I::GamePadDeadZone::Circular)),
      "capabilities" => capabilities_record(I::GamePad.GetCapabilities(player))
    }
  end
  vibration = {
    "playerIndex" => "One", "leftMotor" => 0.0, "rightMotor" => 0.0,
    "cnaResult" => "CNA_RESULT_SUCCESS",
    "applied" => I::GamePad.SetVibration(F::PlayerIndex::One, 0.0, 0.0),
    "qualification" => "route-only all-off request; no physical-rumble claim"
  }
ensure
  game.Dispose
end

connected = records.any? { |record| record.fetch("defaultIndependentAxes").fetch("isConnected") }
report = {
  "schemaVersion" => 1,
  "group" => "GAMEPAD_NATIVE",
  "provenance" => "CNA_NATIVE_INTEGRATION",
  "includedInPureTotals" => false,
  "library" => CNA::Native.library.path,
  "librarySha256" => Digest::SHA256.file(CNA::Native.library.path).hexdigest,
  "platform" => RUBY_PLATFORM,
  "renderer" => "HEADLESS",
  "hardware" => {
    "controllerConnected" => connected,
    "positivePathState" => connected ? "OBSERVED_CONNECTED" : "HARDWARE_PENDING",
    "positivePathCapabilities" => connected ? "OBSERVED_CONNECTED" : "HARDWARE_PENDING",
    "physicalVibration" => "HARDWARE_PENDING"
  },
  "players" => records,
  "setVibration" => vibration,
  "proves" => [
    "all four canonical player-slot routes return managed snapshots",
    "default, None, IndependentAxes and Circular native calls execute",
    "capability snapshots are returned by CNA rather than synthesized in Ruby",
    "the canonical vibration route returns the backend Boolean"
  ],
  "doesNotProve" => [
    connected ? nil : "positive connected-controller state",
    connected ? nil : "positive capability flags",
    "physical motor actuation"
  ].compact
}

destination = File.expand_path("../docs/generated/gamepad-native-report.json", __dir__)
File.write(destination, JSON.pretty_generate(report) + "\n")
puts "GAMEPAD_NATIVE_PLAYERS=#{records.length}"
puts "CONTROLLER_CONNECTED=#{connected ? "YES" : "NO"}"
puts "VIBRATION_ROUTE_APPLIED=#{vibration.fetch("applied") ? "YES" : "NO"}"
puts "PHYSICAL_VIBRATION=HARDWARE_PENDING"
