# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # Only the pure managed XNA Audio enum contracts and the three Audio exception types are
      # projected. No audio engine, SoundEffect, Microphone, XACT or CNA audio route is implemented
      # or implied; nothing in this binding ever raises these exceptions.
      module Audio
        # Each of the three declares nothing but the standard trio of constructors, every one of
        # which the pinned XNA IL shows forwarding straight to its CLR exception base.
        # InstancePlayLimitException and NoAudioHardwareException derive from
        # System.Runtime.InteropServices.ExternalException, which the BCL projection register
        # collapses to the same Ruby StandardError root as System.Exception.
        class InstancePlayLimitException < StandardError
          include CNA::Runtime::XnaExceptionConstruction
        end

        class NoAudioHardwareException < StandardError
          include CNA::Runtime::XnaExceptionConstruction
        end

        class NoMicrophoneConnectedException < StandardError
          include CNA::Runtime::XnaExceptionConstruction
        end

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
