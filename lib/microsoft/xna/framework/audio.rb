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

        # Derived from the pinned Microsoft.Xna.Framework.Xact.dll IL.
        #
        # `.class public sequential ansi sealed beforefieldinit`, extending `System.ValueType` over
        # two private `string` fields and declaring seven identities. It is **entirely pure managed**:
        # not one of the seven touches a device, an engine or a native route, and every body is a
        # field read, a string comparison or an XOR.
        #
        # Its frontier deferral was `RUNTIME_DATA` -- "values come from XACT audio renderer
        # enumeration; no audio engine exists in this binding and no renderer has been enumerated" --
        # and that is a statement about the **producer**, not the type. Foundation 25 settled exactly
        # this case for `Graphics.DisplayMode`: a CLR class whose only constructor is `assembly`
        # projects with construction made private, and completing it implies nothing about the
        # enumerator that would fill it. Native frontier 4 measured what the audio backend really
        # does, and none of it is needed here.
        #
        # `.ctor(string name, string id)` is `assembly` -- two `stfld`, no validation -- so `new` is
        # private and reachable only as `RendererDetail.__send__(:new, name, id)`.
        class RendererDetail
          include CNA::Runtime::ValueSemantics

          attr_reader :FriendlyName, :RendererId

          def initialize(name, id)
            @FriendlyName = name.nil? ? nil : String(name).dup.freeze
            @RendererId = id.nil? ? nil : String(id).dup.freeze
            freeze
          end
          private_class_method :new

          # A CLR value type copies on assignment, and `ValueSemantics#dup` builds the copy through
          # `new`, which is private here. The copy is still the value's own business, so it goes
          # through the same private constructor rather than being given up.
          def dup = self.class.__send__(:new, @FriendlyName, @RendererId)

          # `op_Equality` compares both fields with `String::op_Equality`, which is ordinal, and
          # short-circuits on the name. `op_Inequality` is its negation. `Equals(object)` answers
          # false for null and for a different type before delegating to `op_Equality` -- which is
          # exactly what `ValueSemantics` already does, so no member is redeclared to say it twice.
          #
          # `GetHashCode` is
          #
          #     (IsNullOrEmpty(_name) ? 0 : _name.GetHashCode()) ^ (IsNullOrEmpty(_id) ? 0 : _id.GetHashCode())
          #
          # in that order -- the name's contribution is the left operand of the XOR. Both the
          # empty-or-null-contributes-zero rule and the XOR are reproduced exactly. What is not
          # reproduced is `System.String.GetHashCode`, a Microsoft-internal algorithm; Ruby's own
          # `String#hash` stands in for it. A CLR hash code is documented as implementation-specific
          # and must not be persisted or compared across runtimes, so the observable contract --
          # equal values hash equally, an empty or nil component contributes nothing -- survives
          # intact, and the exact Int32 does not. Recorded as a language-mapping limitation rather
          # than silently approximated.
          def GetHashCode
            name_hash = @FriendlyName.nil? || @FriendlyName.empty? ? 0 : @FriendlyName.hash
            id_hash = @RendererId.nil? || @RendererId.empty? ? 0 : @RendererId.hash
            name_hash ^ id_hash
          end

          # `ToString()` is declared, and its whole body is `ValueType::ToString()`, which answers
          # the type's own fully-qualified CLR name. That is a deterministic string belonging to
          # this very type rather than a localized Microsoft resource, so it is reproduced literally.
          def ToString = "Microsoft.Xna.Framework.Audio.RendererDetail"

          alias to_s ToString

          private

          def value_components = [@FriendlyName, @RendererId]
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
