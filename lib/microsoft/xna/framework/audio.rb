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

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…). Both types are
        # pure managed state holders: every property reads or writes a field of a native-layout XACT
        # struct, and nothing calls into native code. No audio engine, SoundEffect or XACT runtime
        # exists in this binding, so nothing a consumer sets here is ever heard.
        class AudioListener
          include CNA::Runtime::XactSpatialState

          def initialize
            initialize_xact_spatial_state
          end
        end

        class AudioEmitter
          include CNA::Runtime::XactSpatialState

          def initialize
            initialize_xact_spatial_state
            # The constructor also stores DopplerScale 1, and the internal ChannelCount 1,
            # ChannelRadius 1 and CurveDistanceScaler 1, none of which XNA exposes publicly.
            @DopplerScale = CNA::Runtime::Numeric.f32(1.0)
          end

          attr_reader :DopplerScale

          # `ldarg.1; ldc.r4 0.0; bge.un.s` — the branch past the throw is taken when the value is
          # greater than or equal to zero **or unordered**, so NaN is accepted and only an ordered
          # negative value raises. Negative zero compares equal to zero and is accepted too.
          def DopplerScale=(value)
            scale = CNA::Runtime::Numeric.f32(value)
            raise RangeError, "DopplerScale must not be negative" unless scale.nan? || scale >= 0.0

            @DopplerScale = scale
          end
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
