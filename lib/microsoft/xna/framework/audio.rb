# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # Only the pure managed XNA Audio enum contracts are projected. No audio engine,
      # SoundEffect, Microphone, XACT or CNA audio route is implemented or implied.
      module Audio
        class AudioChannels < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Mono" => 1,
            "Stereo" => 2
          })
        end

        class AudioStopOptions < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "AsAuthored" => 0,
            "Immediate" => 1
          })
        end

        class SoundState < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Playing" => 0,
            "Paused" => 1,
            "Stopped" => 2
          })
        end

        class MicrophoneState < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Started" => 0,
            "Stopped" => 1
          })
        end
      end
    end
  end
end
