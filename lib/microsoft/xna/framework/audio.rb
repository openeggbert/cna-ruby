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
        # `.class public auto ansi sealed`, extending `SoundEffectInstance`. It is the streaming
        # instance: a consumer submits PCM16 buffers and the runtime raises `BufferNeeded` when the
        # queue runs low, which is why it is the one `SoundEffectInstance` with a public constructor
        # and no `SoundEffect` behind it. CNA's `cna_dynamic_sound_effect_instance_create` is
        # game-parented for exactly that reason.
        #
        # The constructor's bounds are the same literals `SoundEffect`'s are -- `sampleRate` in
        # `[8000, 48000]`, `channels` in `[1, 2]`, from `ldc.i4 0x1f40`/`0xbb80` -- and every other
        # member opens with the same disposed check.
        #
        # `SubmitBuffer` validates against the instance's own `AudioFormat`, and **block alignment**
        # is the part a summary would lose: the buffer length, the offset and the count must each be
        # a whole number of frames, which for PCM16 is `2 * channels` bytes. A misaligned length is
        # `InvalidAudioBuffer`, a misaligned offset is `InvalidAudioBufferOffset`, and a misaligned
        # or non-positive count is `InvalidOffsetCountLength` -- three different messages for what
        # looks like one rule.
        #
        # `IsLooped` is the inherited property with a **narrower** setter: `set_IsLooped` throws
        # `InvalidOperationException(InvalidDynamicIsLoopedCall)` when the value is `true`, and
        # accepts `false`. A streaming instance cannot loop, because there is nothing fixed to loop
        # over. The getter is inherited unchanged.
        class DynamicSoundEffectInstance < SoundEffectInstance
          extend CNA::Runtime::EventOwner

          # The canonical event carries nothing but its sender, so the handler receives only its
          # context. CNA raises it "from whichever thread advances the queue, which is the game
          # thread when the loop runs" -- and what advances that queue here is
          # `FrameworkDispatcher.Update`, the member this binding already projects, rather than a
          # second per-instance pump.
          xna_event :BufferNeeded

          public_class_method :new

          def initialize(sampleRate, channels)
            rate = SoundEffect.__send__(:validated_sample_rate, sampleRate)
            channel_count = SoundEffect.__send__(:validated_channels, channels)
            host = CNA::Runtime::Context.native_host("DynamicSoundEffectInstance.new")
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_dynamic_sound_effect_instance_create", host.handle,
                                     rate, channel_count, output)
            @block_align = 2 * channel_count
            @buffer_registration = 0
            @buffer_callback = nil
            initialize_dynamic(output[0, 8].unpack1("Q"))
            subscribe_buffer_needed
          end

          # `Dispose(Boolean)` is the one member this type declares that its base also has, and the
          # reference confirms it: `protected Dispose(System.Boolean)`. It releases the buffer-needed
          # registration before the base releases the instance, so the callback can never be raised
          # against a handle that is already gone.
          def Dispose(disposing = true)
            release_buffer_registration
            super
          end

          def PendingBufferCount
            ensure_live!
            output = CNA::Native.library.pointer_for("l", 0)
            CNA::Native.library.call("cna_dynamic_sound_effect_instance_get_pending_buffer_count",
                                     native_handle, output)
            output[0, 4].unpack1("l")
          end

          # `SubmitBuffer(byte[])` is `SubmitBuffer(buffer, 0, buffer.Length)`; Ruby collapses the
          # two overloads into one method with defaults, the rule every other overload set follows.
          def SubmitBuffer(buffer, offset = nil, count = nil)
            ensure_live!
            raise ArgumentError, "buffer" if buffer.nil?
            raise TypeError, "buffer must be a String of bytes" unless buffer.is_a?(::String)

            bytes = buffer.b
            length = bytes.bytesize
            raise ArgumentError, "buffer" if length.zero? || (length % @block_align) != 0

            start = offset.nil? ? 0 : CNA::Runtime::Numeric.int32(offset, "offset")
            taken = count.nil? ? length : CNA::Runtime::Numeric.int32(count, "count")
            raise ArgumentError, "offset" if start.negative? || start >= length || (start % @block_align) != 0
            raise ArgumentError, "count" if start + taken > length
            raise ArgumentError, "count" if taken <= 0 || (taken % @block_align) != 0

            CNA::Native.library.call("cna_dynamic_sound_effect_instance_submit_buffer", native_handle,
                                     Fiddle::Pointer[bytes], length, start, taken)
            nil
          end

          # `if (sizeInBytes < 0) throw new ArgumentException(InvalidBufferSize)`, and the answer is
          # a TimeSpan, which this binding projects as seconds.
          def GetSampleDuration(sizeInBytes)
            ensure_live!
            size = CNA::Runtime::Numeric.int32(sizeInBytes, "sizeInBytes")
            raise ArgumentError, "sizeInBytes" if size.negative?

            output = CNA::Native.library.pointer_for("q", 0)
            CNA::Native.library.call("cna_dynamic_sound_effect_instance_get_sample_duration_ticks",
                                     native_handle, size, output)
            output[0, 8].unpack1("q") / 10_000_000.0
          end

          def GetSampleSizeInBytes(duration)
            ensure_live!
            seconds = CNA::Runtime::BclProjection.time_span(duration)
            raise ::RangeError, "duration" if seconds.nan? || seconds.negative?

            output = CNA::Native.library.pointer_for("l", 0)
            CNA::Native.library.call("cna_dynamic_sound_effect_instance_get_sample_size_in_bytes",
                                     native_handle, (seconds * 10_000_000).round, output)
            output[0, 4].unpack1("l")
          end

          # `Play` asks for the initial buffers before starting, which is what makes a streaming
          # instance different from an ordinary one: the queue has to be primed or the first frame
          # plays silence.
          def Play
            ensure_live!
            CNA::Native.library.call("cna_dynamic_sound_effect_instance_queue_initial_buffers_ext",
                                     native_handle)
            super
          end

          # `set_IsLooped` is the one member this type narrows rather than adds: a streaming
          # instance has nothing fixed to loop over, so `true` is refused and `false` is accepted.
          def IsLooped=(value)
            ensure_live!
            raise ::RuntimeError, "a DynamicSoundEffectInstance cannot loop" if value

            super
          end

          private

          def initialize_dynamic(handle)
            @effect = nil
            @looped = false
            @volume = CNA::Runtime::Numeric.f32(1.0)
            @pitch = CNA::Runtime::Numeric.f32(0.0)
            @pan = CNA::Runtime::Numeric.f32(0.0)
            @is_3d = false
            @packet_submitted = false
            game = CNA::Runtime::Context.__send__(:current_game, "DynamicSoundEffectInstance")
            initialize_native_resource(game, handle,
                                       lambda { |value| CNA::Native.library.call("cna_sound_effect_instance_destroy", value) })
            self
          end

          # The parent's guard also checks the owning `SoundEffect`; this type has none.
          def ensure_live!
            raise CNA::DisposedObjectError, "#{type_name} is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end

          def subscribe_buffer_needed
            @buffer_callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]) do |_context|
              begin
                self.BufferNeeded.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
              rescue ::Exception # rubocop:disable Lint/RescueException
                nil
              end
              nil
            end
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_dynamic_sound_effect_instance_subscribe_buffer_needed",
                                     native_handle, @buffer_callback, nil, output)
            @buffer_registration = output[0, 8].unpack1("Q")
          rescue CNA::NativeError
            # `CNA_RESULT_INVALID_STATE` for an instance that does not stream. Nothing is lost: the
            # event simply never fires, which is the honest state rather than a fabricated one.
            @buffer_registration = 0
            @buffer_callback = nil
          end

          def release_buffer_registration
            return if @buffer_registration.zero?

            begin
              CNA::Native.library.call("cna_audio_unsubscribe_ext", @buffer_registration)
            rescue CNA::Error
              nil
            end
            @buffer_registration = 0
            @buffer_callback = nil
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

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…), together with
        # `Audio.AudioFormat`, `Audio.AudioHelper.MakeFormat` and `Audio.MicrophoneCollection` from
        # the same assembly, and `System.TimeSpan.Interval` from the pinned Microsoft .NET Framework
        # 4.0 mscorlib (SHA-256 5634668d…).
        #
        # Native frontier 4 recorded this type `NATIVE_RUNTIME`. It is the sixth candidate that word
        # was wrong about. This machine really has three capture devices, CNA enumerates all three
        # with their hardware names, and the sixteen `cna_microphone_*` routes are declared
        # identically by the retired 0.7.0 headers as well -- so the classification was never about
        # the ABI, and never about the host either.
        #
        # ## Identity, and why there is no handle
        #
        # XNA's `Microphone` wraps a `uint32` handle from `CreateMicrophone(index, out handle)`.
        # CNA has **no microphone handle at all**: every route is `(CNA_Handle game, uint64_t index,
        # …)`, so a device is named by its position in the machine's list and the runtime owns it.
        # The projection therefore carries a `BORROWED_EXTERNAL_SCALAR` index and nothing else.
        # Nothing is destroyed, which is also why `Finalize` -- the one member XNA declares that
        # frees a handle -- projects here as the member that does nothing.
        #
        # DEVIATION, recorded: XNA's collection is a **CLR static** built in a static constructor,
        # so `Microphone.All` needs nothing at all. Every CNA route takes a game handle, so `All`
        # and `Default` need a live Game on its owner thread. That is the same asymmetry
        # `FrameworkDispatcher` and the `SoundEffect` statics record.
        #
        # ## Where the arithmetic lives, and why it is not CNA's
        #
        # CNA exports `cna_microphone_get_sample_duration_ticks_at` and
        # `cna_microphone_get_sample_size_in_bytes_at`, and they **measurably disagree with XNA**.
        # XNA computes both in managed code through `AudioFormat`, in `float`, over a format that is
        # always mono PCM16 at the device rate -- `AudioFormat.Create(GetSampleRate(), 1, 16)` -- and
        # the float32 rounding is observable:
        #
        #     GetSampleSizeInBytes(100ms) : XNA 8818   CNA 8820
        #     GetSampleSizeInBytes(1000ms): XNA 88198  CNA 88200
        #     GetSampleDuration(8818)     : XNA 100ms  CNA 99ms
        #     GetSampleDuration(46)       : XNA 1ms    CNA 0ms
        #
        # XNA truncates `duration_ms * (float)(rate / 1000f)` toward zero, and `AudioFormat` is what
        # produces the 4409-rather-than-4410 samples; CNA computes exactly. In the other direction
        # `TimeSpan.FromMilliseconds` rounds half away from zero -- `(long)(ms + 0.5) * 10000` in the
        # pinned mscorlib -- and CNA truncates. So the projection does the arithmetic itself, in the
        # order the IL does it, and the two CNA routes are bound and reachable through
        # `native_sample_size_in_bytes` / `native_sample_duration_ticks` so the divergence is
        # measured by a test rather than only described here.
        #
        # `docs/microphone-evidence.md` records every measurement.
        class Microphone
          extend CNA::Runtime::EventOwner

          CLR_IDENTITY = "Microsoft.Xna.Framework.Audio.Microphone"

          # `AudioFormat.Create(GetSampleRate(), 1, 16)` in the constructor, and
          # `MakeFormat(rate, channels, bits)` writes `BlockAlign = channels * bits / 8`. A
          # microphone is mono PCM16 on every device, so the block align is two bytes and
          # `samples % Channels` -- which the IL really computes -- is always zero.
          CHANNELS = 1
          BITS_PER_SAMPLE = 16
          BLOCK_ALIGN = 2

          # `set_BufferDuration` refuses outside `[100, 1000]` milliseconds or off a 10 ms boundary,
          # with `ArgumentOutOfRangeException("value", InvalidMicrophoneBufferDuration)`. The three
          # literals are `ldc.r8 100`, `ldc.r8 1000` and `ldc.r8 10` in the IL.
          BUFFER_DURATION_MINIMUM_MILLISECONDS = 100
          BUFFER_DURATION_MAXIMUM_MILLISECONDS = 1000
          BUFFER_DURATION_GRANULARITY_MILLISECONDS = 10

          # `new StringBuilder(0x104)` -- MAX_PATH -- is the capacity XNA gives `GetName`. CNA asks
          # its own size first, so this is recorded rather than used as a limit.
          XNA_NAME_CAPACITY = 0x104

          # `MicrophoneCollection.OnBufferReady` raises it with `EventArgs.Empty` on the microphone
          # whose handle matches, so the handler receives the device and an empty argument.
          xna_event :BufferReady

          private_class_method :new

          class << self
            # `get_All` is `EnumerateMicrophones(); return collection;` -- it re-enumerates on every
            # read and answers the **same** `ReadOnlyCollection` object, which wraps a `List` that
            # only ever grows. `EnumerateMicrophones` throws `InvalidOperationException` when the
            # device count has **fallen**, because an index that was handed out cannot be withdrawn.
            def All
              enumerate
              @collection
            end

            # `if (defaultMic == null) SelectDefaultMicrophone(); return defaultMic;`, and
            # `SelectDefaultMicrophone` takes the first device the platform calls default, falling
            # back to index 0 when none says so and the collection is not empty. So this answers
            # `nil` only when the machine has no capture device at all.
            def Default
              enumerate
              return @default if @default

              @default = @devices[default_index] || @devices.first
            end

            private

            def enumerate
              host = CNA::Runtime::Context.native_host("Microphone.All")
              reset_for(host)
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_microphone_get_count", host.handle, output)
              count = output[0, 8].unpack1("Q")
              # `if (count < allMicrophones.Count) throw new InvalidOperationException()`.
              raise ::RuntimeError, "the microphone count fell from #{@devices.length} to #{count}" if count < @devices.length

              (@devices.length...count).each { |index| @devices << __send__(:new, host, index) }
              nil
            end

            # XNA's collection is a process-global static; this one is keyed on the CNA game that
            # produced it, because the indices only mean anything to that game. A second game gets a
            # fresh enumeration rather than the first game's devices.
            def reset_for(host)
              return if defined?(@host_handle) && @host_handle == host.handle

              @host_handle = host.handle
              @devices = []
              @default = nil
              @collection = CNA::Runtime::ReadOnlyCollection.new(@devices)
            end

            def default_index
              host = CNA::Runtime::Context.native_host("Microphone.Default")
              index = CNA::Native.library.pointer_for("Q", 0)
              available = CNA::Native.library.pointer_for("C", 0)
              CNA::Native.library.call("cna_microphone_get_default_index_ext", host.handle, index, available)
              return nil if available[0, 1].unpack1("C").zero?

              index[0, 8].unpack1("Q")
            end
          end

          # `public string Name` is a **field**, not a property: read once in the constructor from
          # `GetName()` and never written again. A Ruby reader is the field's projection, and the
          # value is frozen because a CLR string is immutable.
          attr_reader :Name

          def initialize(host, index)
            @host = host
            @index = index
            @sample_rate = read_sample_rate
            @Name = read_name.freeze
            @buffer_duration_ticks = read_buffer_duration_ticks
            @registration = 0
            @callback = nil
            subscribe_buffer_ready
          end

          # `get_State` reads the device every time: `GetState(Handle, out state)` then
          # `state == 1 ? Started : Stopped`. The native identity and the managed one are inverted
          # in XNA and **not** in CNA, whose `CNA_MICROPHONE_STATE_STARTED` is 0 exactly as
          # `MicrophoneState.Started` is, so the projection passes the value through.
          def State
            output = CNA::Native.library.pointer_for("L", 0)
            call("cna_microphone_get_state_at", output)
            MicrophoneState.coerce(output[0, 4].unpack1("L"))
          end

          # `get_SampleRate` answers `format.SampleRate`, and the format is built once in the
          # constructor. So this is the rate the device reported when it was enumerated, not a fresh
          # read -- which is observable if a device changes rate under a running game.
          def SampleRate = @sample_rate

          # DEVIATION, recorded: `isHeadset` has exactly one writer in the whole assembly --
          # `ldc.i4.1` in the constructor -- so XNA 4.0 on Windows answers `true` for every device,
          # which is what a program ported from XNA observes. CNA answers the platform truth, and on
          # this machine that is `false` for all three devices. The projection answers XNA's
          # constant, because a consumer's branch has to go the way XNA's does; the device's own
          # answer stays reachable through `native_is_headset` and a test asserts both.
          def IsHeadset = true

          # `get_BufferDuration` returns the cached field, not a device read -- so it answers what
          # was last **requested**, which is what makes the deviation below observable rather than
          # hidden.
          def BufferDuration = @buffer_duration_ticks / 10_000_000.0

          # `if (ms < 100 || ms > 1000 || ms % 10 != 0) throw new ArgumentOutOfRangeException(...)`,
          # then `SetCaptureBufferDuration(Handle, (int)ms)`, then store the field.
          #
          # DEVIATION, recorded: CNA's accepted domain is `[100, 990]` milliseconds on a 10 ms
          # boundary -- measured tick by tick, not read from a document -- so the single value XNA
          # admits that CNA refuses is exactly 1000 ms. That value is also the device's **own
          # initial** buffer duration, which `cna_microphone_get_buffer_duration_ticks_at` reports as
          # 10 000 000 ticks, so `set(get())` fails upstream. Rather than raise where XNA does not,
          # the projection sends the largest duration CNA accepts and caches the requested one, which
          # is the value XNA's getter would answer. `docs/microphone-evidence.md` §4 records the
          # sweep and classifies the upstream inconsistency.
          def BufferDuration=(value)
            ticks = self.class.__send__(:ticks_from, value, "value")
            milliseconds = ticks / 10_000.0
            if milliseconds < BUFFER_DURATION_MINIMUM_MILLISECONDS ||
               milliseconds > BUFFER_DURATION_MAXIMUM_MILLISECONDS ||
               (milliseconds % BUFFER_DURATION_GRANULARITY_MILLISECONDS) != 0
              raise ::RangeError, "value"
            end

            call("cna_microphone_set_buffer_duration_ticks_at", [ticks, CNA_MAXIMUM_BUFFER_DURATION_TICKS].min)
            @buffer_duration_ticks = ticks
            value
          end

          # `if (sizeInBytes < 0) throw new ArgumentException(InvalidBufferSize)`, `TimeSpan.Zero`
          # for zero, and `AudioFormat.DurationFromSize` otherwise.
          def GetSampleDuration(sizeInBytes)
            size = CNA::Runtime::Numeric.int32(sizeInBytes, "sizeInBytes")
            raise ::ArgumentError, "sizeInBytes" if size.negative?
            return 0.0 if size.zero?

            duration_from_size(size) / 10_000_000.0
          end

          # `if (ms < 0 || !(ms <= int.MaxValue)) throw new ArgumentOutOfRangeException("duration")`
          # -- the second comparison is `ble.un`, so a NaN passes it and is refused further in, by
          # the `conv.ovf.i4` whose `OverflowException` the method catches and rethrows as the same
          # `ArgumentOutOfRangeException("duration")`. Zero answers zero before the format is asked.
          def GetSampleSizeInBytes(duration)
            seconds = CNA::Runtime::BclProjection.time_span(duration)
            raise ::RangeError, "duration" if seconds.nan?

            ticks = (seconds * 10_000_000).round
            milliseconds = ticks / 10_000.0
            raise ::RangeError, "duration" if milliseconds.negative? || milliseconds > 2_147_483_647
            return 0 if ticks.zero?

            size_from_duration(milliseconds)
          end

          # `Start()` and `Stop()` are one native call each under the instance lock, with no managed
          # state change of their own: the state machine lives entirely in the device, which is why
          # `State` re-reads it.
          def Start
            call("cna_microphone_start_at")
            nil
          end

          def Stop
            call("cna_microphone_stop_at")
            nil
          end

          # `GetData(byte[])` is `GetData(buffer, 0, buffer.Length)` after validating the buffer, and
          # Ruby collapses the two overloads into one method with defaults, the rule every other
          # overload set in this binding follows.
          #
          # The validation order is the IL's, and each stage names the resource string XNA names:
          #
          #   1. null, empty or unaligned buffer          -> InvalidAudioBuffer
          #   2. offset negative, past the end, unaligned -> InvalidAudioBufferOffset
          #   3. offset + count overflowing int32         -> InvalidOffsetCountLength
          #   4. count <= 0, past the end, unaligned, or
          #      lasting zero milliseconds                -> InvalidOffsetCountLength
          #
          # Stage 4's last clause is the one that surprises: `DurationFromSize(count) == Zero` after
          # `TimeSpan.FromMilliseconds` has rounded, so on a 44 100 Hz device every aligned count
          # below 46 bytes is refused even though it fits the buffer.
          #
          # `if (State != Started) return 0;` is the last step before the read, so a stopped
          # microphone answers zero rather than raising -- and that is the whole of the managed
          # contract, reachable without ever opening the device.
          def GetData(buffer, offset = nil, count = nil)
            raise ::ArgumentError, "buffer" unless buffer.is_a?(::String)

            length = buffer.bytesize
            raise ::ArgumentError, "buffer" if length.zero? || (length % BLOCK_ALIGN) != 0

            start = offset.nil? ? 0 : CNA::Runtime::Numeric.int32(offset, "offset")
            taken = count.nil? ? length : CNA::Runtime::Numeric.int32(count, "count")
            raise ::ArgumentError, "offset" if start.negative? || start >= length || (start % BLOCK_ALIGN) != 0

            # `add.ovf` inside a `try` whose catch rethrows as InvalidOffsetCountLength.
            finish = start + taken
            raise ::ArgumentError, "count" if finish > 2_147_483_647 || finish < -2_147_483_648
            raise ::ArgumentError, "count" if taken <= 0 || finish <= 0 || finish > length
            raise ::ArgumentError, "count" if (taken % BLOCK_ALIGN) != 0 || duration_from_size(taken).zero?

            # A CLR `byte[]` is never frozen and cannot be resized; a Ruby String is both, so the
            # write target is refused rather than resized, which is the rule `CNA::Runtime::Stream`
            # already sets for every buffer this binding fills.
            raise ::ArgumentError, "buffer must not be frozen" if buffer.frozen?
            return 0 unless self.State == MicrophoneState::Started

            destination = Fiddle::Pointer.malloc(taken, Fiddle::RUBY_FREE)
            read = CNA::Native.library.pointer_for("Q", 0)
            call("cna_microphone_get_data_at", destination, taken, read)
            bytes = read[0, 8].unpack1("Q")
            buffer[start, bytes] = destination[0, bytes] if bytes.positive?
            bytes
          end

          protected

          # `try { if (Handle != -1) DestroyMicrophone(Handle); } finally { base.Finalize(); }`.
          # There is no handle here and CNA's runtime owns the device, so this destroys nothing --
          # and, as everywhere in this binding, projecting the member registers no Ruby finalizer.
          # Nothing native is ever released by the garbage collector.
          def Finalize = nil

          private

          # The largest buffer duration CNA accepts, measured by sweeping every whole millisecond in
          # `[95, 1005]` and every tick in `[1_000_000, 1_000_020]`: the predicate is
          # `(ticks / 10_000) % 10 == 0 && 100 <= ticks / 10_000 <= 990`, on integer division.
          CNA_MAXIMUM_BUFFER_DURATION_TICKS = 9_900_000

          def call(symbol, *arguments)
            CNA::Native.library.call(symbol, @host.handle, @index, *arguments)
          end

          def read_sample_rate
            output = CNA::Native.library.pointer_for("l", 0)
            call("cna_microphone_get_sample_rate_at", output)
            output[0, 4].unpack1("l")
          end

          def read_name
            size = CNA::Native.library.pointer_for("Q", 0)
            call("cna_microphone_get_name_size_at", size)
            bytes = size[0, 8].unpack1("Q")
            return "" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            call("cna_microphone_copy_name_at", buffer, bytes, required)
            buffer[0, bytes].force_encoding(Encoding::UTF_8)
          end

          def read_buffer_duration_ticks
            output = CNA::Native.library.pointer_for("q", 0)
            call("cna_microphone_get_buffer_duration_ticks_at", output)
            output[0, 8].unpack1("q")
          end

          # The closure is retained for the registration's lifetime, this binding's standing rule for
          # a callback that crosses into C, and a Ruby exception raised inside it is captured rather
          # than unwound through native frames.
          def subscribe_buffer_ready
            @callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]) do |_context|
              begin
                self.BufferReady.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
              rescue ::Exception # rubocop:disable Lint/RescueException
                nil
              end
              nil
            end
            output = CNA::Native.library.pointer_for("Q", 0)
            call("cna_microphone_subscribe_buffer_ready_at", @callback, nil, output)
            @registration = output[0, 8].unpack1("Q")
          rescue CNA::NativeError
            @registration = 0
            @callback = nil
          end

          # `AudioFormat.DurationFromSize`: `TimeSpan.FromMilliseconds((float)(size / BlockAlign) *
          # 1000f / (float)SampleRate)`, every arithmetic step at binary32 and the result rounded to
          # a whole millisecond by `TimeSpan.Interval`. Answers ticks, which is what a TimeSpan is.
          def duration_from_size(size_in_bytes)
            samples = size_in_bytes / BLOCK_ALIGN
            scaled = CNA::Runtime::Numeric.f32(CNA::Runtime::Numeric.f32(samples) * 1000.0)
            milliseconds = CNA::Runtime::Numeric.f32(scaled / CNA::Runtime::Numeric.f32(@sample_rate))
            self.class.__send__(:ticks_from_milliseconds, milliseconds)
          end

          # `AudioFormat.SizeFromDuration`: `samples = (int)(ms * ((float)SampleRate / 1000f))` then
          # `(samples + samples % Channels) * BlockAlign`, with `conv.ovf.i4` on the first step and
          # `add.ovf`/`mul.ovf` on the second. Every overflow is caught by `GetSampleSizeInBytes` and
          # rethrown as `ArgumentOutOfRangeException("duration")`.
          def size_from_duration(milliseconds)
            scale = CNA::Runtime::Numeric.f32(CNA::Runtime::Numeric.f32(@sample_rate) / 1000.0)
            product = milliseconds * scale
            raise ::RangeError, "duration" if product.nan? || product >= 2_147_483_648.0 || product < -2_147_483_648.0

            samples = product.truncate
            size = (samples + (samples % CHANNELS)) * BLOCK_ALIGN
            raise ::RangeError, "duration" unless size.between?(-2_147_483_648, 2_147_483_647)

            size
          end

          # The device's own answers, which the projection does not use because they disagree with
          # XNA. They exist so the disagreement is measured rather than asserted in prose.
          def native_is_headset
            output = CNA::Native.library.pointer_for("C", 0)
            call("cna_microphone_get_is_headset_at", output)
            !output[0, 1].unpack1("C").zero?
          end

          def native_sample_duration_ticks(size_in_bytes)
            output = CNA::Native.library.pointer_for("q", 0)
            call("cna_microphone_get_sample_duration_ticks_at", size_in_bytes, output)
            output[0, 8].unpack1("q")
          end

          def native_sample_size_in_bytes(ticks)
            output = CNA::Native.library.pointer_for("l", 0)
            call("cna_microphone_get_sample_size_in_bytes_at", ticks, output)
            output[0, 4].unpack1("l")
          end

          def native_buffer_duration_ticks = read_buffer_duration_ticks

          class << self
            private

            # A TimeSpan is an integer tick count, and every XNA comparison in this type is on
            # `TotalMilliseconds`, which is `ticks / 10000.0`. Converting the projected seconds to
            # ticks first is what makes `100 ms % 10 == 0` exact rather than a binary64 artifact.
            def ticks_from(value, name)
              seconds = CNA::Runtime::BclProjection.time_span(value)
              raise ::RangeError, name if seconds.nan? || seconds.infinite?

              (seconds * 10_000_000).round
            end

            # `TimeSpan.Interval(value, 1)` from the pinned mscorlib: reject NaN, add half a
            # millisecond away from zero, refuse beyond ±922 337 203 685 477, truncate, and scale by
            # 10 000 ticks. So a TimeSpan built this way is always a whole number of milliseconds.
            def ticks_from_milliseconds(milliseconds)
              raise ::ArgumentError, "value" if milliseconds.nan?

              rounded = milliseconds + (milliseconds >= 0 ? 0.5 : -0.5)
              raise ::RangeError, "value" if rounded > 922_337_203_685_477 || rounded < -922_337_203_685_477

              rounded.truncate * 10_000
            end
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.Xact.dll IL (SHA-256 a14d5364…).
        #
        # `AudioCategory` is a **struct** over three fields -- the owning engine, a `uint16` category
        # index and the name -- and its constructor is `assembly`, so a consumer reaches one only
        # through `AudioEngine.GetCategory`. It declares no `Dispose` and no finalizer: the category
        # belongs to the engine, not to the value that names it.
        #
        # CNA hands out a **handle** where XNA carries a `uint16`, and two `cna_audio_engine_get_category`
        # calls for one name answer two different handles -- measured -- so `AudioEngine.GetCategory`
        # caches by name. That makes handle equality exactly XNA's `_category ==`, gives the engine a
        # bounded set of `PARENT_OWNED` handles to release, and is asserted against CNA's own
        # `cna_audio_category_equals` rather than assumed.
        class AudioCategory
          include CNA::Runtime::ValueSemantics

          CLR_IDENTITY = "Microsoft.Xna.Framework.Audio.AudioCategory"

          private_class_method :new

          # `if (engine == null) throw new ArgumentNullException("engine", NullNotAllowed)` and the
          # same for a null or empty name, then `GetCategory` and
          # `if (_category == 0xffff) throw new InvalidOperationException(CouldNotCreateResource)`.
          def initialize(engine, name, handle)
            @parent = engine
            @Name = name
            @handle = handle
          end

          # One `ldfld`. XNA never normalises it, so a category's name is the string the consumer
          # passed rather than the one the engine reports; `ToString` is where the null case is
          # handled instead.
          attr_reader :Name

          # `if (!(volume >= 0f)) throw new ArgumentException(InvalidXactVolume)`. The comparison is
          # `bge.un` -- **unordered** -- so `NaN` takes the *accepting* branch, which is the exact
          # opposite of `SoundEffectInstance.Volume`, whose `blt.un`/`bgt.un` make NaN throw. Both
          # asymmetries are the IL's and both are reproduced.
          #
          # DEVIATION, recorded: `cna_audio_category_set_volume` accepts a negative volume without
          # complaint, so the refusal is managed-side exactly as XNA's is and CNA never sees one.
          def SetVolume(volume)
            ensure_live!
            number = CNA::Runtime::Numeric.f32(volume)
            raise ::ArgumentError, "volume" if number.negative?

            call("cna_audio_category_set_volume", number)
            nil
          end

          # `Engine::Pause(engine, category, 1)` and `Engine::Pause(engine, category, 0)` -- one
          # native entry point with a flag, which CNA splits into two routes.
          def Pause
            ensure_live!
            call("cna_audio_category_pause")
            nil
          end

          def Resume
            ensure_live!
            call("cna_audio_category_resume")
            nil
          end

          def Stop(options)
            ensure_live!
            raise ::TypeError, "options must be AudioStopOptions" unless options.instance_of?(AudioStopOptions)

            call("cna_audio_category_stop", options.to_i)
            nil
          end

          # `return _name ?? String.Empty` -- the one member that handles a null name.
          def ToString = @Name.nil? ? "" : @Name

          # `_category.GetHashCode() ^ _parent.GetHashCode()`, and the parent term is added only when
          # the parent is non-null. CNA's `get_hash_code` answers the same value for two handles
          # naming one category, which is what makes it the analogue of XNA's `uint16` hash.
          def GetHashCode
            output = CNA::Native.library.pointer_for("l", 0)
            call("cna_audio_category_get_hash_code", output)
            value = output[0, 4].unpack1("l")
            @parent.nil? ? value : (value ^ @parent.hash)
          end

          def to_s = self.ToString

          private

          def value_components = [@parent, @handle]

          def call(symbol, *arguments) = CNA::Native.library.call(symbol, @handle, *arguments)

          def ensure_live!
            raise CNA::DisposedObjectError, "AudioEngine is disposed" if @parent.nil? || @parent.IsDisposed
          end

          # The mechanism behind the cache, kept reachable so a test can assert that handle equality
          # and CNA's own notion of category equality agree rather than trusting the cache.
          def native_equals?(other)
            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_audio_category_equals", @handle,
                                     other.instance_variable_get(:@handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def native_name
            size = CNA::Native.library.pointer_for("Q", 0)
            call("cna_audio_category_get_name_size", size)
            bytes = size[0, 8].unpack1("Q")
            return "" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            call("cna_audio_category_copy_name", buffer, bytes, required)
            buffer[0, bytes].force_encoding(Encoding::UTF_8)
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.Xact.dll IL (SHA-256 a14d5364…).
        #
        # `Audio.AudioCategory` sat in the frontier's `RUNTIME_DATA` register with the reasoning
        # "an XACT AudioEngine category handle; SetVolume/Pause/Resume/Stop act on a live engine this
        # binding does not have". Both halves were about the producer, and the second is no longer
        # true: CNA 0.21.0 loads a real XGS -- six categories and eight variables out of the XNA
        # Spacewar sample's `SpaceWar.xgs` -- and answers a real `SDL3_mixer` renderer.
        #
        # ## The constructor validates the file before the engine sees it
        #
        # `AudioEngine(settingsFile)` is `AudioEngine(settingsFile, TimeSpan.FromMilliseconds(250),
        # null)`, and the three-argument form:
        #
        #   * `if (string.IsNullOrEmpty(settingsFile)) throw ArgumentNullException("settingsFile")`
        #   * opens the file and reads four bytes; if it is four bytes or shorter, or those bytes are
        #     not `X G S F`, `ArgumentException(InvalidContentVersion)` -- so a wrong file is refused
        #     in managed code, by magic number, before XACT is asked
        #   * `Engine::CreateHandle(fullPath, (int)lookAheadTime.TotalMilliseconds, rendererId)`, and
        #     `-1` becomes `InvalidOperationException(CouldNotCreateResource)`
        #
        # DEVIATION, recorded: `cna_audio_engine_create` is **game-parented** where XNA's constructor
        # needs no Game -- the asymmetry every game-scoped audio route in this binding records.
        class AudioEngine
          include CNA::Runtime::NativeResource
          extend CNA::Runtime::EventOwner

          CLR_IDENTITY = "Microsoft.Xna.Framework.Audio.AudioEngine"

          # `.field public static literal int32 ContentVersion = int32(0x00000027)`.
          ContentVersion = 39

          # `TimeSpan.FromMilliseconds(250)` in the one-argument constructor, projected as seconds.
          DEFAULT_LOOK_AHEAD_SECONDS = 0.25

          # The four bytes the constructor reads before XACT is asked for anything.
          SETTINGS_MAGIC = "XGSF"

          xna_event :Disposing

          def initialize(settingsFile, lookAheadTime = nil, rendererId = nil)
            raise ::ArgumentError, "settingsFile" if settingsFile.nil?

            path = String(settingsFile)
            raise ::ArgumentError, "settingsFile" if path.empty?

            verify_settings_magic!(path)
            seconds = lookAheadTime.nil? ? DEFAULT_LOOK_AHEAD_SECONDS : CNA::Runtime::BclProjection.time_span(lookAheadTime)
            raise ::RangeError, "lookAheadTime" if seconds.nan?

            host = CNA::Runtime::Context.native_host("AudioEngine.new")
            output = CNA::Native.library.pointer_for("Q", 0)
            full = File.expand_path(path)
            file = CNA::Native::Layouts::StringView.new(full.b)
            renderer = CNA::Native::Layouts::StringView.new((rendererId.nil? ? "" : String(rendererId)).b)
            CNA::Native.library.call("cna_audio_engine_create_with_renderer", host.handle,
                                     file.read_u64(0), file.read_u64(8),
                                     (seconds * 10_000_000).round,
                                     renderer.read_u64(0), renderer.read_u64(8), output)
            @categories = {}
            @banks = []
            @registration = 0
            @callback = nil
            initialize_native_resource(
              CNA::Runtime::Context.__send__(:current_game, "AudioEngine"),
              output[0, 8].unpack1("Q"),
              lambda { |value| CNA::Native.library.call("cna_audio_engine_destroy", value) }
            )
          end

          # `return new AudioCategory(this, name)`, and the constructor it calls is what validates.
          # The cache is this binding's, for the reason `AudioCategory` records.
          def GetCategory(name)
            ensure_live!
            raise ::ArgumentError, "name" if name.nil?

            key = String(name)
            raise ::ArgumentError, "name" if key.empty?

            handle = @categories[key]
            unless handle
              output = CNA::Native.library.pointer_for("Q", 0)
              view = CNA::Native::Layouts::StringView.new(key.b)
              begin
                CNA::Native.library.call("cna_audio_engine_get_category", native_handle,
                                         view.read_u64(0), view.read_u64(8), output)
              rescue CNA::NativeError
                # `if (_category == 0xffff) throw new InvalidOperationException(CouldNotCreateResource)`.
                raise ::RuntimeError, "could not create resource"
              end
              handle = output[0, 8].unpack1("Q")
              @categories[key] = handle
            end
            AudioCategory.__send__(:new, self, key, handle)
          end

          # `if (string.IsNullOrEmpty(name)) throw new ArgumentNullException("name")`, then the
          # native call whose result becomes an exception.
          #
          # Measured on the Spacewar settings: `SpeedOfSound` answers 343.5 and round-trips, and the
          # other seven names in the file are **cue-instance** variables rather than global ones, so
          # XACT refuses them here. That refusal is the engine's, not this binding's.
          def GetGlobalVariable(name)
            ensure_live!
            key = validated_name(name)
            output = CNA::Native.library.pointer_for("f", 0.0)
            view = CNA::Native::Layouts::StringView.new(key.b)
            CNA::Native.library.call("cna_audio_engine_get_global_variable", native_handle,
                                     view.read_u64(0), view.read_u64(8), output)
            output[0, 4].unpack1("f")
          end

          def SetGlobalVariable(name, value)
            ensure_live!
            key = validated_name(name)
            view = CNA::Native::Layouts::StringView.new(key.b)
            CNA::Native.library.call("cna_audio_engine_set_global_variable", native_handle,
                                     view.read_u64(0), view.read_u64(8),
                                     CNA::Runtime::Numeric.f32(value))
            nil
          end

          def Update
            ensure_live!
            CNA::Native.library.call("cna_audio_engine_update", native_handle)
            nil
          end

          # `GetRendererCount`, then one `GetRenderDetails` per index into a `List<RendererDetail>`
          # wrapped in a `ReadOnlyCollection`. The local holding the answer starts as `ldnull`, so a
          # renderer count of zero or less answers **null** rather than an empty collection -- an
          # observable this reproduces rather than smoothing over.
          def RendererDetails
            ensure_live!
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_audio_engine_get_renderer_count", native_handle, output)
            count = output[0, 8].unpack1("Q")
            return nil if count.zero?

            details = (0...count).map do |index|
              RendererDetail.__send__(:new,
                                      renderer_string(index, "friendly_name"),
                                      renderer_string(index, "id"))
            end
            CNA::Runtime::ReadOnlyCollection.new(details)
          end

          # `public void Dispose() => Dispose(true); GC.SuppressFinalize(this);` and
          # `protected virtual void Dispose(bool disposing)`, which raises `Disposing` before the
          # engine handle goes. Ruby cannot give one name two visibilities, so the two overloads
          # project to one public method with a default argument -- the rule `Game`,
          # `ContentManager` and `SoundEffectInstance` already follow.
          #
          # Every category handle this engine handed out is released here, before the engine itself:
          # they are `PARENT_OWNED`, XNA declares nothing that would release them, and a category
          # outliving its engine would be a handle into a destroyed XACT engine.
          def Dispose(_disposing = true)
            return if self.IsDisposed

            self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty)
            release_registration
            # CNA refuses to destroy an engine while a bank of its own is still alive, the same
            # requirement the sound bank records for its cues. XNA leaves both to the CLR.
            @banks.dup.each { |bank| bank.Dispose unless bank.IsDisposed }
            @banks.clear
            @categories.each_value do |handle|
              begin
                CNA::Native.library.call("cna_audio_category_destroy", handle)
              rescue CNA::Error
                nil
              end
            end
            @categories.clear
            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            nil
          end

          private

          # `try { Dispose(false); } finally { base.Finalize(); }`, and no Ruby finalizer is ever
          # registered: nothing native in this binding is released by the garbage collector.
          def Finalize
            self.Dispose(false)
            nil
          end

          # A `def … = expr unless cond` endless definition binds the modifier to the *definition*,
          # not the body, so this one is spelled out.
          def register_bank(bank)
            @banks << bank unless @banks.any? { |value| value.equal?(bank) }
          end

          def unregister_bank(bank) = @banks.reject! { |value| value.equal?(bank) }

          def verify_settings_magic!(path)
            magic = File.open(path, "rb") { |io| io.read(5) }
            raise ::ArgumentError, "settingsFile" if magic.nil? || magic.bytesize <= 4
            raise ::ArgumentError, "settingsFile" unless magic.byteslice(0, 4) == SETTINGS_MAGIC
          end

          def validated_name(name)
            raise ::ArgumentError, "name" if name.nil?

            key = String(name)
            raise ::ArgumentError, "name" if key.empty?

            key
          end

          def renderer_string(index, kind)
            size = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_audio_engine_get_renderer_#{kind}_size", native_handle, index, size)
            bytes = size[0, 8].unpack1("Q")
            return "" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_audio_engine_copy_renderer_#{kind}", native_handle, index,
                                     buffer, bytes, required)
            buffer[0, bytes].force_encoding(Encoding::UTF_8)
          end

          def ensure_live!
            raise CNA::DisposedObjectError, "AudioEngine is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end

          def release_registration
            return if @registration.zero?

            begin
              CNA::Native.library.call("cna_audio_unsubscribe_ext", @registration)
            rescue CNA::Error
              nil
            end
            @registration = 0
            @callback = nil
          end
        end

        # `WaveBank(AudioEngine, String)` and `WaveBank(AudioEngine, String, Int32, Int16)`, the
        # second of which is the streaming form. Nine identities, no member that plays anything: a
        # wave bank is the data a sound bank's cues draw on.
        class WaveBank
          include CNA::Runtime::NativeResource
          extend CNA::Runtime::EventOwner

          CLR_IDENTITY = "Microsoft.Xna.Framework.Audio.WaveBank"

          # `CheckWaveBankHeader` compares `bytes[0..3]` with `W B N D` -- `ldc.i4.s 87, 66, 78, 68`.
          MAGIC = "WBND"

          xna_event :Disposing

          # `if (audioEngine == null) throw new ArgumentNullException("audioEngine", RequireNonNullAudioEngine)`
          # and a null or empty filename raises `ArgumentNullException` naming whichever parameter
          # this overload has -- `nonStreamingWaveBankFilename` or `streamingWaveBankFilename`. Ruby
          # collapses the two overloads into one method with defaults, so the *streaming* form is the
          # one where `offset` is given.
          def initialize(audioEngine, filename, offset = nil, packetsize = nil)
            engine = CNA::Runtime::Audio.validated_engine!(audioEngine)
            streaming = !offset.nil? || !packetsize.nil?
            argument = streaming ? "streamingWaveBankFilename" : "nonStreamingWaveBankFilename"
            path = File.expand_path(CNA::Runtime::Audio.validated_name!(filename, argument))
            CNA::Runtime::Audio.verify_magic!(path, MAGIC, argument)

            output = CNA::Native.library.pointer_for("Q", 0)
            view = CNA::Native::Layouts::StringView.new(path.b)
            if streaming
              CNA::Native.library.call("cna_wave_bank_create_streaming", engine.__send__(:native_handle),
                                       view.read_u64(0), view.read_u64(8),
                                       CNA::Runtime::Numeric.int32(offset || 0, "offset"),
                                       CNA::Runtime::Numeric.int32(packetsize || 0, "packetsize"),
                                       output)
            else
              CNA::Native.library.call("cna_wave_bank_create", engine.__send__(:native_handle),
                                       view.read_u64(0), view.read_u64(8), output)
            end
            @parent = engine
            engine.__send__(:register_bank, self)
            initialize_native_resource(
              CNA::Runtime::Context.__send__(:current_game, "WaveBank"),
              output[0, 8].unpack1("Q"),
              lambda { |value| CNA::Native.library.call("cna_wave_bank_destroy", value) }
            )
          end

          # `(GetStatus() & 0x80) != 0` and `(GetStatus() & 4) != 0` -- XACT's status bitmask, which
          # CNA reads out as two flags.
          def IsInUse = flag("cna_wave_bank_get_is_in_use")
          def IsPrepared = flag("cna_wave_bank_get_is_prepared")

          # The `Dispose(bool)` shape every XACT type in this file shares. Ruby cannot give one name
          # two visibilities, so the public `Dispose()` and the protected `Dispose(Boolean)` project
          # to one method with a default argument.
          def Dispose(disposing = true)
            return if self.IsDisposed

            self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty) if disposing
            @parent.__send__(:unregister_bank, self)
            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            nil
          end

          private

          def Finalize
            self.Dispose(false)
            nil
          end

          def flag(symbol)
            ensure_live!
            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call(symbol, native_handle, output)
            !output[0, 1].unpack1("C").zero?
          end

          def ensure_live!
            raise CNA::DisposedObjectError, "WaveBank is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end
        end

        # `SoundBank(AudioEngine, String)`, ten identities, and the type that produces every `Cue`.
        class SoundBank
          include CNA::Runtime::NativeResource
          extend CNA::Runtime::EventOwner

          CLR_IDENTITY = "Microsoft.Xna.Framework.Audio.SoundBank"

          # The constructor reads four bytes and compares them with `S D B K` -- `ldc.i4.s 83, 68,
          # 66, 75` at indices 0..3 -- refusing anything shorter first.
          MAGIC = "SDBK"

          xna_event :Disposing

          def initialize(audioEngine, filename)
            engine = CNA::Runtime::Audio.validated_engine!(audioEngine)
            path = File.expand_path(CNA::Runtime::Audio.validated_name!(filename, "filename"))
            CNA::Runtime::Audio.verify_magic!(path, MAGIC, "filename")

            output = CNA::Native.library.pointer_for("Q", 0)
            view = CNA::Native::Layouts::StringView.new(path.b)
            CNA::Native.library.call("cna_sound_bank_create", engine.__send__(:native_handle),
                                     view.read_u64(0), view.read_u64(8), output)
            @parent = engine
            @cues = []
            engine.__send__(:register_bank, self)
            initialize_native_resource(
              CNA::Runtime::Context.__send__(:current_game, "SoundBank"),
              output[0, 8].unpack1("Q"),
              lambda { |value| CNA::Native.library.call("cna_sound_bank_destroy", value) }
            )
          end

          def IsInUse
            ensure_live!
            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_sound_bank_get_is_in_use", native_handle, output)
            !output[0, 1].unpack1("C").zero?
          end

          # `if (string.IsNullOrEmpty(name)) throw new ArgumentNullException("name")`, then XACT. A
          # name the bank does not know answers `E_INVALIDARG` there, which XNA turns into
          # `ArgumentException(string.Format(CueNotFound, name))` rather than letting the raw error
          # through -- so an unknown cue is an argument problem, not a state one.
          def GetCue(name)
            ensure_live!
            key = CNA::Runtime::Audio.validated_name!(name, "name")
            output = CNA::Native.library.pointer_for("Q", 0)
            view = CNA::Native::Layouts::StringView.new(key.b)
            begin
              CNA::Native.library.call("cna_sound_bank_get_cue", native_handle,
                                       view.read_u64(0), view.read_u64(8), output)
            rescue CNA::NativeError
              raise ::ArgumentError, "cue not found: #{key}"
            end
            cue = Cue.__send__(:new, self, key, output[0, 8].unpack1("Q"))
            @cues << cue
            cue
          end

          # `PlayCue(String)` fires and forgets: the cue it makes is never handed back, and the one
          # error XACT is allowed to answer without raising is `0x8ac70008`, the cue-instance limit.
          # Anything else becomes `InvalidOperationException(CueNotFound)` -- an *operation* problem
          # here, where `GetCue` reports an *argument* one for the same underlying error.
          #
          # `PlayCue(String, AudioListener, AudioEmitter)` is the same with a 3D apply before the
          # play, and Ruby collapses the two overloads into one method with defaults.
          def PlayCue(name, listener = nil, emitter = nil)
            ensure_live!
            key = CNA::Runtime::Audio.validated_name!(name, "name")
            view = CNA::Native::Layouts::StringView.new(key.b)
            begin
              if listener.nil? && emitter.nil?
                CNA::Native.library.call("cna_sound_bank_play_cue", native_handle,
                                         view.read_u64(0), view.read_u64(8))
              else
                raise ::ArgumentError, "listener" if listener.nil?
                raise ::ArgumentError, "emitter" if emitter.nil?

                CNA::Native.library.call("cna_sound_bank_play_cue_3d", native_handle,
                                         view.read_u64(0), view.read_u64(8),
                                         CNA::Runtime::Audio.listener(listener).pointer,
                                         CNA::Runtime::Audio.emitter(emitter).pointer)
              end
            rescue CNA::NativeError
              raise ::RuntimeError, "cue not found: #{key}"
            end
            nil
          end

          # DEVIATION, recorded: CNA refuses `cna_sound_bank_destroy` while any cue of that bank is
          # still alive -- "All C Cue children must be destroyed before their SoundBank" -- where
          # XNA's `SoundBank.Dispose` releases the bank and leaves a live `Cue` behind for the CLR
          # to collect. So this bank disposes the cues it produced first. That is the same enforced
          # parent/child destruction the `SoundEffect` cluster records, and it is CNA's requirement
          # rather than a rule this binding invented.
          def Dispose(disposing = true)
            return if self.IsDisposed

            self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty) if disposing
            @cues.dup.each { |cue| cue.Dispose(disposing) unless cue.IsDisposed }
            @cues.clear
            @parent.__send__(:unregister_bank, self)
            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            nil
          end

          private

          def Finalize
            self.Dispose(false)
            nil
          end

          def forget_cue(cue) = @cues.reject! { |value| value.equal?(cue) }

          def ensure_live!
            raise CNA::DisposedObjectError, "SoundBank is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end
        end

        # `Audio.Cue`, nineteen identities, sealed, and the last type of the XACT cluster.
        #
        # It has no public constructor: `SoundBank.GetCue` and the three-argument `SoundBank.PlayCue`
        # are the only producers, which is why `new` is private here.
        #
        # The seven state properties are one XACT status bitmask -- `IsCreated` 1, `IsPreparing` 2,
        # `IsPrepared` 4, `IsPlaying` 8, `IsStopping` 0x10, `IsStopped` 0x20, `IsPaused` 0x40 -- and
        # each XNA getter calls `GetStatus` afresh. CNA answers all seven at once in `CNA_CueInfo`,
        # and each projected property reads it once, which is the same number of native reads.
        class Cue
          include CNA::Runtime::NativeResource
          extend CNA::Runtime::EventOwner

          CLR_IDENTITY = "Microsoft.Xna.Framework.Audio.Cue"

          # XACT's cue-instance limit. `Play` tolerates exactly this result and raises on any other,
          # which is the one place XNA lets a native failure through silently.
          CUE_INSTANCE_LIMIT_RESULT = 0x8ac7_0008

          xna_event :Disposing

          private_class_method :new

          def initialize(bank, name, handle)
            @bank = bank
            @Name = name.dup.freeze
            @played = false
            @applied_3d = false
            initialize_native_resource(
              CNA::Runtime::Context.__send__(:current_game, "Cue"),
              handle,
              lambda { |value| CNA::Native.library.call("cna_cue_destroy", value) }
            )
          end

          # One `ldfld` over the name the sound bank was asked for.
          attr_reader :Name

          def IsCreated = info.read_u8(8) != 0
          def IsPreparing = info.read_u8(13) != 0
          def IsPrepared = info.read_u8(12) != 0
          def IsPlaying = info.read_u8(11) != 0
          def IsStopping = info.read_u8(15) != 0
          def IsStopped = info.read_u8(14) != 0
          def IsPaused = info.read_u8(10) != 0

          # `Play` compares the native result with `0x8ac70008` -- XACT's cue-instance limit -- and
          # only calls `ThrowExceptionFromResult` when it differs, so that one failure is tolerated
          # silently and every other raises. `played = true` is set afterwards, and it is what
          # `Apply3D` guards on.
          #
          # DEVIATION, recorded: `CNA_Result` has no code for the cue-instance limit, so the
          # tolerated failure cannot be told apart from a real one. Nothing is swallowed on a guess:
          # every native failure raises. The exemption was also **measured unreachable** here --
          # sixty consecutive plays of one cue all succeeded -- so no behaviour that this artifact
          # can produce is lost by not implementing it.
          def Play
            ensure_live!
            CNA::Native.library.call("cna_cue_play", native_handle)
            @played = true
            nil
          end

          # `Cue::Pause(handle, 1)` and `Cue::Pause(handle, 0)` -- one entry point with a flag, which
          # CNA splits into two routes, exactly as it does for `AudioCategory`.
          def Pause
            ensure_live!
            CNA::Native.library.call("cna_cue_pause", native_handle)
            nil
          end

          def Resume
            ensure_live!
            CNA::Native.library.call("cna_cue_resume", native_handle)
            nil
          end

          def Stop(options)
            ensure_live!
            raise ::TypeError, "options must be AudioStopOptions" unless options.instance_of?(AudioStopOptions)

            CNA::Native.library.call("cna_cue_stop", native_handle, options.to_i)
            nil
          end

          def GetVariable(name)
            ensure_live!
            key = CNA::Runtime::Audio.validated_name!(name, "name")
            output = CNA::Native.library.pointer_for("f", 0.0)
            view = CNA::Native::Layouts::StringView.new(key.b)
            CNA::Native.library.call("cna_cue_get_variable", native_handle,
                                     view.read_u64(0), view.read_u64(8), output)
            output[0, 4].unpack1("f")
          end

          def SetVariable(name, value)
            ensure_live!
            key = CNA::Runtime::Audio.validated_name!(name, "name")
            view = CNA::Native::Layouts::StringView.new(key.b)
            CNA::Native.library.call("cna_cue_set_variable", native_handle,
                                     view.read_u64(0), view.read_u64(8),
                                     CNA::Runtime::Numeric.f32(value))
            nil
          end

          # `if (listener == null) throw new ArgumentNullException("listener")`, the same for the
          # emitter, and then the guard that matters:
          #
          #     if (!applied3D && played) throw new InvalidOperationException(Apply3DBeforePlay);
          #
          # So the *first* apply must happen before the first play, and every later one is allowed.
          # This is the same rule `SoundEffectInstance.Apply3D` carries, and it is reproduced
          # managed-side for the same reason: it is a managed rule, not XACT's.
          def Apply3D(listener, emitter)
            ensure_live!
            raise ::ArgumentError, "listener" if listener.nil?
            raise ::ArgumentError, "emitter" if emitter.nil?
            raise ::RuntimeError, "Apply3D must be called before Play" if !@applied_3d && @played

            CNA::Native.library.call("cna_cue_apply_3d", native_handle,
                                     CNA::Runtime::Audio.listener(listener).pointer,
                                     CNA::Runtime::Audio.emitter(emitter).pointer)
            @applied_3d = true
            nil
          end

          def Dispose(disposing = true)
            return if self.IsDisposed

            self.Disposing.__send__(:dispatch, self, CNA::Runtime::EventArgs::Empty) if disposing
            @bank.__send__(:forget_cue, self)
            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            nil
          end

          private

          def Finalize
            self.Dispose(false)
            nil
          end

          def info
            ensure_live!
            output = CNA::Native::Layouts::CueInfo.new
            CNA::Native.library.call("cna_cue_get_info", native_handle, output.pointer)
            output
          end

          # The name XACT reports back, kept reachable so a test can assert it against the name the
          # sound bank was asked for rather than trusting that they agree.
          def native_name
            ensure_live!
            size = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_cue_get_name_size", native_handle, size)
            bytes = size[0, 8].unpack1("Q")
            return "" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            required = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_cue_copy_name", native_handle, buffer, bytes, required)
            buffer[0, bytes].force_encoding(Encoding::UTF_8)
          end

          def ensure_live!
            raise CNA::DisposedObjectError, "Cue is disposed" if self.IsDisposed

            @native_handle.generation.assert_owner_thread!
          end
        end
      end
    end
  end
end
