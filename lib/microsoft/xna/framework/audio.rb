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

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # Native frontier 4 recorded this cluster `UPSTREAM_CNA_BLOCKED`. The CNA C ABI migration
        # re-measured it: the retired artifact had been built `CNA_AUDIO_PLATFORM=NULL`, a build-time
        # CMake choice, and the audit's control variable `CNA_AUDIO` is read by nothing. On the
        # current artifact the whole path is behaviourally real -- one second of PCM16 answers
        # exactly 10 000 000 ticks and the state machine moves through every transition -- so the
        # cluster is reopened. `docs/audio-playback-audit-evidence.md` records the whole correction.
        #
        # ## Where the validation lives, and why
        #
        # XNA's three instance setters range-check in **managed** code and then call XACT:
        # `Volume` refuses outside `[0, 1]`, `Pitch` and `Pan` outside `[-1, 1]`, each with
        # `ArgumentOutOfRangeException("value")`. Every one of those comparisons is `blt.un`/`bgt.un`
        # — **unordered**, so `NaN` takes the throw branch, which is a real observable and is
        # reproduced.
        #
        # CNA's three answer differently from each other and from XNA: `set_volume` accepts anything
        # unclamped, `set_pitch` clamps to `[-1, 1]`, and only `set_pan` refuses. So the projection
        # validates managed-side exactly as XNA does and CNA never sees an out-of-range value. That
        # is not a preference: it is the only arrangement under which the three properties behave
        # alike, which is what XNA's contract says they do.
        class SoundEffectInstance
          include CNA::Runtime::NativeResource
          private_class_method :new

          # `Apply3D` sets `is3d`, and `set_Pan` clears it again unless a packet has been submitted:
          #
          #     if (!isPacketSubmitted) is3d = false;
          #     if (is3d) throw new InvalidOperationException(InvalidPanCall);
          #
          # So a 3D call made **before the first play** does not lock `Pan` out, and one made after
          # does. That is surprising enough to be worth stating, and it is reproduced exactly.
          def Play
            ensure_live!
            call("cna_sound_effect_instance_play")
            @packet_submitted = true
            nil
          end

          def Pause
            ensure_live!
            call("cna_sound_effect_instance_pause")
            nil
          end

          def Resume
            ensure_live!
            call("cna_sound_effect_instance_resume")
            nil
          end

          # `Stop()` is `Stop(true)`; the Boolean chooses an immediate stop over one that runs to
          # the end of the authored sound.
          def Stop(immediate = true)
            ensure_live!
            CNA::Native.library.call("cna_sound_effect_instance_stop", native_handle, immediate ? 1 : 0)
            nil
          end

          def State
            ensure_live!
            SoundState.coerce(info.read_u32(8))
          end

          def Volume
            ensure_live!
            @volume
          end

          def Volume=(value)
            ensure_live!
            @volume = ranged(value, 0.0, 1.0)
            CNA::Native.library.call("cna_sound_effect_instance_set_volume", native_handle, @volume)
            @volume
          end

          def Pitch
            ensure_live!
            @pitch
          end

          def Pitch=(value)
            ensure_live!
            @pitch = ranged(value, -1.0, 1.0)
            CNA::Native.library.call("cna_sound_effect_instance_set_pitch", native_handle, @pitch)
            @pitch
          end

          def Pan
            ensure_live!
            @pan
          end

          def Pan=(value)
            ensure_live!
            @is_3d = false unless @packet_submitted
            raise ::RuntimeError, "Pan cannot be set on an instance already positioned with Apply3D" if @is_3d

            @pan = ranged(value, -1.0, 1.0)
            CNA::Native.library.call("cna_sound_effect_instance_set_pan", native_handle, @pan)
            @pan
          end

          def IsLooped
            ensure_live!
            @looped
          end

          # `if (isPacketSubmitted) throw new InvalidOperationException(InvalidIsLoopedCall)`, then
          # one `stfld`. CNA enforces the same rule natively -- `CNA_RESULT_INVALID_STATE` once
          # playback has begun -- and the managed guard is kept so the refusal carries XNA's identity
          # rather than a translated native error.
          def IsLooped=(value)
            ensure_live!
            raise ::RuntimeError, "IsLooped cannot change once playback has begun" if @packet_submitted

            @looped = value ? true : false
            CNA::Native.library.call("cna_sound_effect_instance_set_is_looped", native_handle, @looped ? 1 : 0)
            @looped
          end

          # `UnsafeApply3D` opens with the mirror image of `set_Pan`'s guard:
          #
          #     if (!isPacketSubmitted) is3d = true;
          #     if (!is3d) throw new InvalidOperationException(InvalidApply3DCall);
          #
          # So a first 3D call is always allowed before playback and refused after it, and a
          # *second* one on an instance already positioned in 3D is allowed at any time. CNA enforces
          # the identical rule natively -- "Apply3D cannot be called on a playing instance that is
          # not using 3D audio" -- and the managed guard is kept so the refusal carries XNA's
          # identity rather than a translated native error, exactly as `IsLooped` does.
          def Apply3D(listener, emitter)
            ensure_live!
            listeners = listener.is_a?(::Array) ? listener : [listener]
            raise ArgumentError, "listeners" if listeners.empty?
            raise TypeError, "emitter must be an AudioEmitter" unless emitter.is_a?(AudioEmitter)

            @is_3d = true unless @packet_submitted
            unless @is_3d
              raise ::RuntimeError,
                    "Apply3D cannot be called on an instance that began playing without 3D audio"
            end

            block = CNA::Runtime::Audio.listener_block(listeners)
            CNA::Native.library.call("cna_sound_effect_instance_apply_3d_multi_ext", native_handle,
                                     block, listeners.length, CNA::Runtime::Audio.emitter(emitter).pointer)
            @is_3d = true
            nil
          end

          # `public void Dispose() => Dispose(true); GC.SuppressFinalize(this);` and
          # `protected virtual void Dispose(bool disposing)`. Unlike `GameComponent`'s, this
          # `Dispose(bool)` has **no** `if (!disposing) return` guard: it locks, checks IsDisposed,
          # marks disposed, tells its SoundEffect and deallocates the voice whichever way it is
          # called. So the finalizer path really would release the voice in the CLR. Ruby cannot give
          # one name two visibilities, so the two overloads project to one public method with a
          # default argument -- the rule `Game` and `ContentManager` already follow -- and the
          # widening is recorded.
          def Dispose(_disposing = true)
            return if self.IsDisposed

            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            nil
          end

          private

          # `try { Dispose(false); } finally { base.Finalize(); }`. Ruby's garbage collector never
          # calls it: no `ObjectSpace.define_finalizer` is registered here and none is invented,
          # which is also why `GC.SuppressFinalize` in `Dispose()` needs no analogue.
          def Finalize
            self.Dispose(false)
            nil
          end

          def type_name = self.class.name.split("::").last

          def initialize_instance(effect, handle)
            @effect = effect
            @looped = false
            @volume = CNA::Runtime::Numeric.f32(1.0)
            @pitch = CNA::Runtime::Numeric.f32(0.0)
            @pan = CNA::Runtime::Numeric.f32(0.0)
            @is_3d = false
            @packet_submitted = false
            initialize_native_resource(effect.__send__(:native_game), handle,
                                       lambda { |value| CNA::Native.library.call("cna_sound_effect_instance_destroy", value) })
            self
          end

          def native_handle = @native_handle.value

          def ensure_live!
            raise CNA::DisposedObjectError, "#{type_name} is disposed" if self.IsDisposed
            raise CNA::DisposedObjectError, "#{type_name} is disposed" if @effect.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end

          def call(symbol) = CNA::Native.library.call(symbol, native_handle)

          def info
            snapshot = CNA::Native::Layouts::SoundEffectInstanceInfo.new
            CNA::Native.library.call("cna_sound_effect_instance_get_info", native_handle, snapshot.pointer)
            snapshot
          end

          # `blt.un`/`bgt.un` against the two bounds: NaN is unordered with both, so it takes the
          # throw branch. `value.nan?` reproduces that rather than relying on Ruby comparison, which
          # answers false for every NaN comparison and would silently accept it.
          def ranged(value, low, high)
            number = CNA::Runtime::Numeric.f32(value)
            raise ::RangeError, "value" if number.nan? || number < low || number > high

            number
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public auto ansi sealed`, implementing `IDisposable`. Every constructor validates
        # in managed code before it reaches XACT, and the bounds are literals in the IL rather than
        # documentation: `sampleRate` outside `[8000, 48000]` -- `0x1f40` to `0xbb80` -- and
        # `channels` outside `[1, 2]` each raise `ArgumentOutOfRangeException` naming the parameter,
        # and a null or empty buffer raises `ArgumentException(InvalidAudioBuffer)`.
        #
        # DEVIATION, recorded: XNA's four global settings are **CLR statics** and this projection's
        # are game-scoped, because every canonical CNA route takes a game handle. That is the same
        # asymmetry `FrameworkDispatcher` records, and it is why these four need a live Game on its
        # owner thread where XNA's need nothing at all.
        #
        # DEVIATION, recorded: a `SoundEffect` needs a live CNA Game to exist, because
        # `cna_sound_effect_create_pcm16` is game-parented. XNA's constructor needs no Game.
        class SoundEffect
          include CNA::Runtime::NativeResource

          MIN_SAMPLE_RATE = 8_000
          MAX_SAMPLE_RATE = 48_000

          class << self
            # `if (stream == null) throw new ArgumentNullException("stream")` and nothing else before
            # the decode. The projection accepts the `Stream` this binding projects and any Ruby
            # object answering `read`, which is the contract `Texture2D.FromStream` already uses.
            def FromStream(stream)
              raise ArgumentError, "stream" if stream.nil?

              bytes = SoundEffect.__send__(:read_all, stream)
              raise ArgumentError, "the stream carried no audio" if bytes.empty?

              host = CNA::Runtime::Context.native_host("SoundEffect.FromStream")
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_sound_effect_create_from_encoded_ext", host.handle,
                                       Fiddle::Pointer[bytes], bytes.bytesize, output)
              allocate.__send__(:initialize_from_handle, output[0, 8].unpack1("Q"))
            end

            # Both statics are pure computations in XNA and pure computations in CNA -- neither takes
            # a handle -- so these are the only two members of this type that work with no Game.
            def GetSampleDuration(sizeInBytes, sampleRate, channels)
              size = CNA::Runtime::Numeric.int32(sizeInBytes, "sizeInBytes")
              raise ArgumentError, "sizeInBytes" if size.negative?

              rate = validated_sample_rate(sampleRate)
              output = CNA::Native.library.pointer_for("q", 0)
              CNA::Native.library.call("cna_sound_effect_get_sample_duration_ticks", size, rate,
                                       validated_channels(channels), output)
              output[0, 8].unpack1("q") / 10_000_000.0
            end

            def GetSampleSizeInBytes(duration, sampleRate, channels)
              ticks = (CNA::Runtime::BclProjection.time_span(duration) * 10_000_000).round
              rate = validated_sample_rate(sampleRate)
              output = CNA::Native.library.pointer_for("l", 0)
              CNA::Native.library.call("cna_sound_effect_get_sample_size_in_bytes", ticks, rate,
                                       validated_channels(channels), output)
              output[0, 4].unpack1("l")
            end

            # `if (value < 0f || value > 1f) throw new ArgumentOutOfRangeException("value")`.
            def MasterVolume = global_float("cna_sound_effect_get_master_volume")

            def MasterVolume=(value)
              set_global("cna_sound_effect_set_master_volume", ranged_global(value, 0.0, 1.0))
            end

            # `if (value < 0f) throw` -- `blt.un`, so NaN throws.
            def DopplerScale = global_float("cna_sound_effect_get_doppler_scale")

            def DopplerScale=(value)
              number = CNA::Runtime::Numeric.f32(value)
              raise ::RangeError, "value" if number.nan? || number.negative?

              set_global("cna_sound_effect_set_doppler_scale", number)
            end

            # `bge.un` past the throw, so a negative throws and **NaN does not** -- the one place
            # this type's two scale properties disagree, and it is the IL's asymmetry rather than
            # this projection's. Then `if (value <= Single.Epsilon) value = Single.Epsilon`, so zero
            # is accepted and clamped up rather than refused.
            def DistanceScale = global_float("cna_sound_effect_get_distance_scale")

            def DistanceScale=(value)
              number = CNA::Runtime::Numeric.f32(value)
              raise ::RangeError, "value" if number < 0.0

              number = SINGLE_EPSILON if !number.nan? && number <= SINGLE_EPSILON
              set_global("cna_sound_effect_set_distance_scale", number)
            end

            # `if (value <= 0f) throw` -- `ble.un`, so zero, negatives and NaN all throw.
            def SpeedOfSound = global_float("cna_sound_effect_get_speed_of_sound")

            def SpeedOfSound=(value)
              number = CNA::Runtime::Numeric.f32(value)
              raise ::RangeError, "value" if number.nan? || number <= 0.0

              set_global("cna_sound_effect_set_speed_of_sound", number)
            end

            private

            def validated_sample_rate(value)
              rate = CNA::Runtime::Numeric.int32(value, "sampleRate")
              raise ::RangeError, "sampleRate" if rate < MIN_SAMPLE_RATE || rate > MAX_SAMPLE_RATE

              rate
            end

            def validated_channels(value)
              number = value.respond_to?(:to_i) ? value.to_i : value
              raise ::RangeError, "channels" unless [1, 2].include?(number)

              number
            end

            def ranged_global(value, low, high)
              number = CNA::Runtime::Numeric.f32(value)
              raise ::RangeError, "value" if number.nan? || number < low || number > high

              number
            end

            def global_float(symbol)
              host = CNA::Runtime::Context.native_host("SoundEffect global setting")
              output = CNA::Native.library.pointer_for("f", 0.0)
              CNA::Native.library.call(symbol, host.handle, output)
              output[0, 4].unpack1("f")
            end

            def set_global(symbol, value)
              host = CNA::Runtime::Context.native_host("SoundEffect global setting")
              CNA::Native.library.call(symbol, host.handle, value)
              value
            end

            def read_all(stream)
              bytes = if stream.is_a?(CNA::Runtime::Stream)
                        buffer = "\0".b * stream.Length
                        stream.Read(buffer, 0, buffer.bytesize)
                        buffer
                      elsif stream.respond_to?(:read)
                        stream.read
                      else
                        raise TypeError, "stream must be a Stream or respond to read"
                      end
              raise TypeError, "the stream did not answer bytes" unless bytes.is_a?(::String)

              bytes.b
            end
          end

          # `SoundEffect(byte[] buffer, int sampleRate, AudioChannels channels)` and the seven-argument
          # loop-region overload. Ruby cannot overload by parameter count with different meanings, so
          # the loop region is optional and the shorter call is the same method -- the rule
          # `mapping-rules.json` already applies to every other collapsed overload set.
          def initialize(buffer, sampleRate, channels, offset = nil, count = nil, loopStart = nil, loopLength = nil)
            raise ArgumentError, "buffer" if buffer.nil?
            raise TypeError, "buffer must be a String of bytes" unless buffer.is_a?(::String)
            raise ArgumentError, "buffer" if buffer.empty?

            rate = self.class.__send__(:validated_sample_rate, sampleRate)
            channel_count = self.class.__send__(:validated_channels, channels)
            host = CNA::Runtime::Context.native_host("SoundEffect.new")
            info = CNA::Native::Layouts::SoundEffectCreateInfo.new(rate, channel_count)
            output = CNA::Native.library.pointer_for("Q", 0)
            bytes = buffer.b
            pointer = Fiddle::Pointer[bytes]
            if offset.nil? && count.nil? && loopStart.nil? && loopLength.nil?
              CNA::Native.library.call("cna_sound_effect_create_pcm16", host.handle, info.pointer,
                                       pointer, bytes.bytesize, output)
            else
              region = [offset, count, loopStart, loopLength].map.with_index do |value, index|
                CNA::Runtime::Numeric.int32(value, %w[offset count loopStart loopLength][index])
              end
              CNA::Native.library.call("cna_sound_effect_create_pcm16_range_ext", host.handle,
                                       info.pointer, pointer, bytes.bytesize, *region, output)
            end
            initialize_from_handle(output[0, 8].unpack1("Q"))
          end

          def Duration
            ensure_live!
            output = CNA::Native.library.pointer_for("q", 0)
            CNA::Native.library.call("cna_sound_effect_get_duration_ticks", native_handle, output)
            output[0, 8].unpack1("q") / 10_000_000.0
          end

          def Name
            ensure_live!
            size = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_sound_effect_get_name_size", native_handle, size)
            bytes = size[0, 8].unpack1("Q")
            return "" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_sound_effect_copy_name", native_handle, buffer, bytes, required)
            buffer[0, bytes].force_encoding(Encoding::UTF_8)
          end

          # `if (value == null) throw new ArgumentNullException("value")`, after the disposed check.
          def Name=(value)
            ensure_live!
            raise ArgumentError, "value" if value.nil?

            view = CNA::Native::Layouts::StringView.new(String(value).b)
            CNA::Native.library.call("cna_sound_effect_set_name", native_handle,
                                     view.read_u64(0), view.read_u64(8))
            String(value)
          end

          def CreateInstance
            ensure_live!
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_sound_effect_create_instance", native_handle, output)
            SoundEffectInstance.allocate.__send__(:initialize_instance, self, output[0, 8].unpack1("Q"))
          end

          # Fire-and-forget. XNA answers false when the instance pool is exhausted rather than
          # throwing, and CNA answers the same Boolean, so the result is forwarded rather than
          # asserted.
          def Play(volume = nil, pitch = nil, pan = nil)
            ensure_live!
            output = CNA::Native.library.pointer_for("C", 0)
            if volume.nil? && pitch.nil? && pan.nil?
              CNA::Native.library.call("cna_sound_effect_play", native_handle, output)
            else
              CNA::Native.library.call("cna_sound_effect_play_with_settings", native_handle,
                                       ranged(volume, 0.0, 1.0), ranged(pitch, -1.0, 1.0),
                                       ranged(pan, -1.0, 1.0), output)
            end
            output[0, 1].unpack1("C") == 1
          end

          private

          # `try { Dispose(false); } finally { base.Finalize(); }`, and no Ruby finalizer is ever
          # registered for it, so this is the member the contract declares doing the same nothing.
          def Finalize
            self.Dispose
            nil
          end

          def type_name = self.class.name.split("::").last

          SINGLE_EPSILON = 1.401298464324817e-45
          private_constant :SINGLE_EPSILON

          def initialize_from_handle(handle)
            host = CNA::Runtime::Context.native_host("SoundEffect")
            game = CNA::Runtime::Context.__send__(:current_game, "SoundEffect")
            @native_game = game
            initialize_native_resource(game, handle,
                                       lambda { |value| CNA::Native.library.call("cna_sound_effect_destroy", value) })
            self
          end

          def native_game = @native_game

          def native_handle = @native_handle.value

          def ensure_live!
            raise CNA::DisposedObjectError, "#{type_name} is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end

          def ranged(value, low, high)
            number = CNA::Runtime::Numeric.f32(value)
            raise ::RangeError, "value" if number.nan? || number < low || number > high

            number
          end
        end
      end
    end
  end
end
