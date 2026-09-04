# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # The whole XNA 4.0 `Media` namespace: the three enums, the managed holders `Video`,
      # `VisualizationData` and `MediaSource`, `VideoPlayer` over CNA's own video player, and the
      # library and player half -- `MediaLibrary`, `MediaPlayer`, `MediaQueue`, `Song`, `Album`,
      # `Artist`, `Genre`, `Playlist`, `Picture`, `PictureAlbum` and their seven collections --
      # over CNA's own media library.
      #
      # Two limits are real and are recorded rather than worked around. Nothing produces a `Video`,
      # so `VideoPlayer.Play` has no legal argument; and `Song.Album`, `Song.Artist` and
      # `Song.Genre` are the only three members of this namespace CNA exports no route for, which
      # is why `Song` is the one type here that is not complete.
      module Media
        # Pinned CLR declaration order is Paused, Playing, Stopped; the raw values are not ascending.
        class MediaState < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Paused" => 2,
            "Playing" => 1,
            "Stopped" => 0
          })
        end

        class MediaSourceType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "LocalDevice" => 0,
            "WindowsMediaConnect" => 4
          })
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public auto ansi beforefieldinit` over four fields -- two `assembly float32[]` and
        # two private `ReadOnlyCollection`1<float32>` -- and three identities: a **public**
        # parameterless constructor and two get-only properties, each one `ldfld`.
        #
        # Its frontier deferral was `RUNTIME_DATA`, "filled by MediaPlayer.GetVisualizationData from
        # live playback". That is a statement about the **filler**, not the type: the constructor
        # allocates everything it needs and reaches nothing. Foundation 24 settled the same case for
        # `AudioListener` and `AudioEmitter` -- managed holders a consumer can build and set,
        # whose effect nothing here ever hears -- and Foundation 50 for `RendererDetail`.
        #
        # The constructor is seventy-five bytes and does exactly four things:
        #
        #     frequencies = new float[0x100];
        #     samples     = new float[0x100];
        #     frequenciesCollection = new ReadOnlyCollection<float>(frequencies);
        #     samplesCollection     = new ReadOnlyCollection<float>(samples);
        #
        # So both collections are **256 elements long from construction**, every element the CLR
        # `Single` default of zero, and each is a live **view** over the array behind it rather than
        # a snapshot -- which is precisely what `CNA::Runtime::ReadOnlyCollection` projects, and what
        # would let a filler's writes show through. Nothing in this binding is that filler.
        class VisualizationData
          # `new float[0x100]` -- two hundred and fifty-six, twice.
          SIZE = 0x100
          private_constant :SIZE

          def initialize
            @frequencies = ::Array.new(SIZE) { CNA::Runtime::Numeric.f32(0.0) }
            @samples = ::Array.new(SIZE) { CNA::Runtime::Numeric.f32(0.0) }
            @Frequencies = FloatCollection.new(@frequencies)
            @Samples = FloatCollection.new(@samples)
          end

          # Two `ldfld` getters, each answering the same wrapper for the life of the object.
          attr_reader :Frequencies, :Samples

          private

          # `MediaPlayer.GetVisualizationData(this)` fills the caller's object, and the CLR fills
          # the two arrays **in place** rather than replacing them — which is what makes each
          # collection a live view rather than a snapshot, the property Foundation 51 measured.
          def fill_from_native(data)
            data.frequencies.each_with_index { |value, index| @frequencies[index] = value }
            data.samples.each_with_index { |value, index| @samples[index] = value }
            nil
          end

          public

          # `ReadOnlyCollection<float>` closed over `System.Single`. A Ruby class is not statically
          # generic, so the CLR type argument is carried as metadata the API verifier measures.
          class FloatCollection < CNA::Runtime::ReadOnlyCollection
            projects_elements "System.Single"
          end
        end

        # Derived from the pinned Microsoft.Xna.Framework.Video.dll IL.
        #
        # `.class public auto ansi sealed beforefieldinit` over seven private fields, with five
        # public get-only properties -- each one `ldfld` -- and two `assembly` getters,
        # `GraphicsDevice` and `Filename`, which are not identities and are not projected.
        #
        # Its deferral was `RUNTIME_DATA`: "its internal constructor takes a GraphicsDevice, one of
        # the deferred partial runtime types, and builds a Duration from tick components the content
        # pipeline supplies; no producer exists". Both halves are about the **producer**. Naming a
        # partial type in a signature is not a blocker -- Foundation 40 established that a type is
        # blocked only when its own IL *calls a member* of one, and this constructor merely stores
        # the reference -- and "the content pipeline supplies the components" is a statement about
        # who calls the constructor, not about what the type does.
        #
        # The constructor is `assembly`, so `new` is private under the Foundation 25 rule, and it
        # stores all seven arguments with no validation. One conversion is worth naming: `duration`
        # arrives as an `Int32` and the field is built as `new TimeSpan(0, 0, 0, 0, duration)` --
        # the five-argument form, whose last parameter is **milliseconds**. This binding projects
        # `System.TimeSpan` as Float seconds, so the property answers those milliseconds divided by
        # a thousand.
        class Video
          N = CNA::Runtime::Numeric
          private_constant :N

          attr_reader :Duration, :Width, :Height, :FramesPerSecond, :VideoSoundtrackType

          def initialize(device, file, duration, width, height, frames_per_second, soundtrack_type)
            @graphics_device = device
            @filename = file.nil? ? nil : String(file).dup.freeze
            @Duration = CNA::Runtime::BclProjection.time_span(N.int32(duration, "duration") / 1000.0)
            @Width = N.int32(width, "width")
            @Height = N.int32(height, "height")
            @FramesPerSecond = N.f32(frames_per_second)
            @VideoSoundtrackType = Media::VideoSoundtrackType.coerce(soundtrack_type)
            freeze
          end
          private_class_method :new
        end

        # Derived from the pinned Microsoft.Xna.Framework.Video.dll IL (SHA-256 17538b1c…).
        #
        # It reached the frontier reporting `NATIVE_RUNTIME` over fifteen members, and the audit that
        # word demands found the word wrong for the eleventh time: every one of the fifteen has a
        # canonical CNA route, all of them work headless, and the optional video decoder really is
        # compiled into the qualified artifact -- a real file is probed for its real metadata, `Play`
        # moves the state machine to `Playing`, and a frame texture exists.
        # `docs/video-player-audit-evidence.md` is the measurement.
        #
        # Every public member follows the same IL shape:
        #
        #     lock (decoderHandleLock) {
        #         ThrowIfDisposed();                          // ObjectDisposedException(GetType())
        #         if (!IsValidDecoder || activeVideo == null) return;   // or throw, for GetTexture
        #         … one VideoDecoder_* call …
        #     }
        #
        # `IsLooped`, `IsMuted` and `Volume` are the exception: their **getters** are a bare `ldfld`
        # with no lock and no disposal check, so they answer after disposal, while their setters take
        # the lock and throw. That asymmetry is XNA's and is measured in both directions.
        class VideoPlayer
          include CNA::Runtime::NativeResource

          # `volume = 1f` in the constructor, and the setter's range check is `if (value < 0f ||
          # !(value <= 1f)) throw new ArgumentOutOfRangeException("value")`. The second half is
          # `ble.un` -- **unordered** -- so NaN takes the accepting branch, the same asymmetry
          # `AudioCategory.SetVolume` records and the opposite of `SoundEffectInstance.Volume`.
          DEFAULT_VOLUME = 1.0

          # `.ctor()` takes nothing in XNA: it sets its fields and calls `VideoDecoder_Create`.
          # DEVIATION, recorded: `cna_video_player_create` is **game-parented**, the same asymmetry
          # every game-scoped audio and window route in this binding records, so a player can only be
          # built while a game is running.
          def initialize
            host = CNA::Runtime::Context.native_host("VideoPlayer.new")
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_video_player_create", host.handle, output)
            @looping = false
            @muted = false
            @volume = DEFAULT_VOLUME
            initialize_native_resource(
              CNA::Runtime::Context.__send__(:current_game, "VideoPlayer"),
              output[0, 8].unpack1("Q"),
              lambda { |value| CNA::Native.library.call("cna_video_player_destroy", value) }
            )
          end

          # `Dispose(true)` sets `disposed`, destroys the decoder and disposes both frame textures.
          # `Finalize` is `Dispose(false)`; no Ruby finalizer is registered, because nothing in this
          # binding is released by the garbage collector.
          def Dispose(disposing = true)
            return if self.IsDisposed

            CNA::Native.library.call("cna_video_player_dispose", native_handle) if disposing
            @native_handle.dispose
            @native_game.__send__(:unregister_native_child, self)
            nil
          end

          def Finalize
            self.Dispose(false)
            nil
          end

          # `if (!IsValidDecoder || activeVideo == null) throw new InvalidOperationException()` --
          # a **bare** InvalidOperationException with no message, which is what the IL constructs and
          # what the projected `System.InvalidOperationException` maps to. Nothing here can be
          # playing, for the reason `Play` records, so this is the branch a consumer always reaches.
          def GetTexture
            ensure_live!
            output = CNA::Native.library.pointer_for("Q", 0)
            available = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_video_player_get_texture", native_handle, output, available)
            raise ::RuntimeError, "VideoPlayer" if available[0, 1].unpack1("C").zero?

            raise CNA::Runtime::NotSupportedError, NO_VIDEO_PRODUCER
          end

          # `if (video == null) throw new ArgumentNullException("video")` is XNA's own first line and
          # is reproduced; the type check after it is this binding's.
          #
          # DEVIATION, recorded and measured rather than worked around: **nothing in this binding
          # produces a `Video`.** XNA's only producer is `ContentManager.Load<Video>`, and CNA
          # exports no content route for video -- its eight `cna_content_manager_load_*` routes cover
          # effects, models, sound effects, sprite fonts, textures and cubes and nothing else. So
          # `Media.Video` has been producerless since Foundation 52 and this member cannot be handed
          # a legal argument. The route it would call is real and works: the audit drove
          # `cna_video_player_play` against a real file at the C ABI and watched the state machine
          # reach `Playing` with a frame texture available. What is missing is the argument, and
          # inventing a `Video` factory XNA does not declare would be inventing an identity.
          NO_VIDEO_PRODUCER =
            "no Video producer exists: XNA's is ContentManager.Load<Video> and CNA exports no " \
            "content route for video (see docs/video-player-audit-evidence.md)"

          def Play(video)
            ensure_live!
            raise ::ArgumentError, "video" if video.nil?
            raise ::TypeError, "video must be Video" unless video.instance_of?(Video)

            raise CNA::Runtime::NotSupportedError, NO_VIDEO_PRODUCER
          end

          def Pause
            ensure_live!
            CNA::Native.library.call("cna_video_player_pause", native_handle)
            nil
          end

          def Resume
            ensure_live!
            CNA::Native.library.call("cna_video_player_resume", native_handle)
            nil
          end

          def Stop
            ensure_live!
            CNA::Native.library.call("cna_video_player_stop", native_handle)
            nil
          end

          # `get_Video` is `ldfld activeVideo`, so it answers whatever `Play` was last handed --
          # `nil` until then. CNA reports the same thing through an availability flag.
          def Video
            ensure_live!
            output = CNA::Native.library.pointer_for("Q", 0)
            available = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_video_player_get_video", native_handle, output, available)
            return nil if available[0, 1].unpack1("C").zero?

            raise CNA::Runtime::NotSupportedError, NO_VIDEO_PRODUCER
          end

          def State
            ensure_live!
            output = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_video_player_get_state", native_handle, output)
            MediaState.coerce(output[0, 4].unpack1("L"))
          end

          # `TimeSpan.FromMilliseconds(...)` over the decoder's position, projected as seconds by the
          # measured `System.TimeSpan` decision.
          def PlayPosition
            ensure_live!
            output = CNA::Native.library.pointer_for("q", 0)
            CNA::Native.library.call("cna_video_player_get_play_position_ticks", native_handle, output)
            CNA::Runtime::BclProjection.time_span(output[0, 8].unpack1("q") / 10_000_000.0)
          end

          # The three field getters: no lock, no disposal check, so they answer after disposal.
          def IsLooped = @looping
          def IsMuted = @muted
          def Volume = @volume

          def IsLooped=(value)
            ensure_live!
            raise ::TypeError, "value" unless value == true || value == false

            CNA::Native.library.call("cna_video_player_set_is_looped", native_handle, value ? 1 : 0)
            @looping = value
          end

          def IsMuted=(value)
            ensure_live!
            raise ::TypeError, "value" unless value == true || value == false

            CNA::Native.library.call("cna_video_player_set_is_muted", native_handle, value ? 1 : 0)
            @muted = value
          end

          def Volume=(value)
            ensure_live!
            number = CNA::Runtime::Numeric.f32(value)
            raise ::RangeError, "value" if number < 0.0 || (number > 1.0 && !number.nan?)

            CNA::Native.library.call("cna_video_player_set_volume", native_handle, number)
            @volume = number
          end

          private

          # `ThrowIfDisposed()` is `if (IsDisposed) throw new ObjectDisposedException(GetType())`,
          # which this binding maps the way every other disposed-object refusal is mapped.
          def ensure_live!
            raise CNA::DisposedObjectError, "VideoPlayer" if self.IsDisposed

            nil
          end
        end

        class VideoSoundtrackType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Music" => 0,
            "Dialog" => 1,
            "MusicAndDialog" => 2
          })
        end

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…) and its own
        # resource table.
        #
        # `Media.MediaSource` sat in the frontier's `RUNTIME_DATA` register with the reasoning
        # "GetAvailableMediaSources enumerates the host media sources; no media stack has been
        # queried". That is a statement about a producer, and this time the producer does not exist:
        #
        #     IL_0000: ldc.i4.1
        #     IL_0001: newarr Microsoft.Xna.Framework.Media.MediaSource
        #     IL_0007: ldloc.0
        #     IL_0009: newobj instance void Microsoft.Xna.Framework.Media.MediaSource::.ctor()
        #     IL_000e: stelem.ref
        #     IL_0010: ret
        #
        # A one-element array holding one `new MediaSource()`, whose constructor stores
        # `MediaSourceType.LocalDevice` and one resource string. **XNA queries no media stack
        # either.** That is the seventh register entry retired for describing the producer rather
        # than the type, and the plainest of them: there was nothing to query.
        class MediaSource
          CLR_IDENTITY = "Microsoft.Xna.Framework.Media.MediaSource"

          # `.ctor` is `mediaSourceType = 0; name = FrameworkResources.WmpMediaSource`. The resource
          # value was extracted from the pinned assembly's own resource table rather than guessed:
          # entry `WmpMediaSource`, string record at data-section offset 22969.
          #
          # DEVIATION, recorded: this is a **localized** resource string, so XNA's answer depends on
          # the UI culture; the qualified profile is the en-US assembly and this is its value.
          # `cna_media_source_copy_name_at` answers `"Local Device"` for the same source, which a
          # test asserts beside this constant rather than leaving the divergence undescribed.
          WMP_MEDIA_SOURCE = "Local Windows Media Player library"

          private_class_method :new

          class << self
            # One array, one element, every call -- so two calls answer two different arrays holding
            # two different `MediaSource` objects, which is what `newarr` plus `newobj` does.
            def GetAvailableMediaSources = [__send__(:new)]
          end

          def initialize
            @MediaSourceType = MediaSourceType::LocalDevice
            @Name = WMP_MEDIA_SOURCE
          end

          # One `ldfld` each.
          attr_reader :MediaSourceType, :Name

          # `return get_Name()` -- the property, not the field.
          def ToString = self.Name

          def to_s = self.ToString

          private

          # What CNA reports for the same source, kept reachable so a test can measure the
          # divergence rather than this comment being the only record of it. It needs a live Game
          # because every CNA media route is game-scoped, which XNA's static needs no part of.
          def native_sources
            host = CNA::Runtime::Context.native_host("MediaSource.native_sources")
            output = CNA::Native.library.pointer_for("L", 0)
            CNA::Native.library.call("cna_media_source_get_available_count", host.handle, output)
            count = output[0, 4].unpack1("L")
            (0...count).map do |index|
              type = CNA::Native.library.pointer_for("L", 0)
              CNA::Native.library.call("cna_media_source_get_type_at", host.handle, index, type)
              size = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_media_source_get_name_size_at", host.handle, index, size)
              bytes = size[0, 8].unpack1("Q")
              name = ""
              if bytes.positive?
                buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
                required = CNA::Native.library.pointer_for("Q", 0)
                CNA::Native.library.call("cna_media_source_copy_name_at", host.handle, index,
                                         buffer, bytes, required)
                name = buffer[0, bytes].force_encoding(Encoding::UTF_8)
              end
              [MediaSourceType.coerce(type[0, 4].unpack1("L")), name]
            end
          end
        end
        # ------------------------------------------------------------------ the Media namespace
        #
        # Seventeen types over one library, and one shape repeated. `CNA::Runtime::MediaSupport`
        # carries the halves every one of them shares — the handle, the disposal, the collection —
        # because they really are the same IL each time; what each type declares below is only what
        # is its own.
        #
        # ## Where the objects come from
        #
        # `MediaLibrary` is the producer for all of them, and `Song.FromUri` is the one other way in.
        # Every collection is a **live view** over a native list: `MediaLibrary.Songs` answers a new
        # wrapper each call, as XNA's does, because the underlying list is the library's.
        #
        # ## The three members CNA cannot answer
        #
        # `Song.Album`, `Song.Artist` and `Song.Genre` have **no CNA route at all** — measured
        # against the exported surface, where every other member of every one of the seventeen has
        # one. `Song` is therefore the family's only partial type and those three are the only
        # blocked members. `docs/remaining-surface-audit.md` records it.

        # A song. `Duration` is a `TimeSpan`, which the BCL register projects as a Float of seconds.
        class Song
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          # `FromUri(string name, Uri uri)`: XNA refuses a null name or uri with
          # `ArgumentNullException`, then hands both to the media stack. `System.Uri` is not in the
          # BCL register and nothing else in the selected surface names it, so the projection takes
          # the string form a Ruby caller has — which is what CNA's route takes too.
          def self.FromUri(name, uri)
            raise ::ArgumentError, "name" if name.nil?
            raise ::ArgumentError, "uri" if uri.nil?

            game = CNA::Runtime::Context.__send__(:current_game, "Song.FromUri")
            name_view = CNA::Native::Layouts::StringView.new(String(name).b)
            uri_view = CNA::Native::Layouts::StringView.new(String(uri).b)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_song_create_from_uri", game.__send__(:window_host_handle),
                                     name_view.read_u64(0), name_view.read_u64(8),
                                     uri_view.read_u64(0), uri_view.read_u64(8), output)
            allocate.__send__(:initialize_native, output[0, 8].unpack1("Q"))
          end

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("song", @handle)
          end

          def Duration
            verify_not_disposed!
            CNA::Runtime::MediaSupport.seconds(
              CNA::Runtime::MediaSupport.int64("cna_song_get_duration", @handle)
            )
          end

          def IsProtected = media_boolean("cna_song_get_is_protected")
          def IsRated = media_boolean("cna_song_get_is_rated")
          def PlayCount = media_int32("cna_song_get_play_count")
          def Rating = media_int32("cna_song_get_rating")
          def TrackNumber = media_int32("cna_song_get_track_number")

          # The three navigations that make the graph walkable from the song outwards. Each is an
          # `ldfld` in XNA over a field the library filled, so each may be null there; CNA answers
          # the same shape with an availability flag, and reports false for a song built from a URI
          # because such a song has no library context at all.
          #
          # Foundation 103 recorded these as `BLOCKED_UPSTREAM_CNA` on the claim that no route
          # existed. **That was wrong**, and the standing rule caught it: a blocker is re-measured
          # before it is trusted, and `nm -D` on the qualified artifact lists
          # `cna_song_get_album`, `cna_song_get_artist` and `cna_song_get_genre` beside the routes
          # this type already used. Both admitted header roots declare all three.
          def Album = optional_library_entity("cna_song_get_album") { |h| Album.__send__(:from_native, h) }
          def Artist = optional_library_entity("cna_song_get_artist") { |h| Artist.__send__(:from_native, h) }
          def Genre = optional_library_entity("cna_song_get_genre") { |h| Genre.__send__(:from_native, h) }

          # `Equals(object)` is `Equals(obj as Song)`, and `Equals(Song)` compares the handles.
          # `op_Equality` adds the null pair, which Ruby spells with `nil`.
          def Equals(other)
            return false unless other.is_a?(Song)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_song_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_song_get_hash_code", @handle)
          end

          private

          def optional_library_entity(symbol)
            verify_not_disposed!
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          public

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_song_dispose"
          def media_destroy_route = "cna_song_destroy"

          def media_boolean(symbol)
            verify_not_disposed!
            CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          end

          def media_int32(symbol)
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32(symbol, @handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `Album`: a media item. Its `Name`, disposal, equality and hash are the family's shape;
        # what is below is what this one adds.
        class Album
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("album", @handle)
          end

          def Artist
            verify_not_disposed!
            optional("cna_album_get_artist") { |h| Artist.__send__(:from_native, h) }
          end

          def Genre
            verify_not_disposed!
            optional("cna_album_get_genre") { |h| Genre.__send__(:from_native, h) }
          end

          def Songs
            verify_not_disposed!
            SongCollection.__send__(:from_native, view("cna_album_get_songs"))
          end

          def Duration
            verify_not_disposed!
            CNA::Runtime::MediaSupport.seconds(media_int64("cna_album_get_duration"))
          end

          def HasArt
            verify_not_disposed!
            media_boolean("cna_album_get_has_art")
          end

          # `GetAlbumArt()` answers a `Stream` over the album's own art, or **null** when it has
          # none — `HasArt` is the question a caller asks first. The bytes come back whole from
          # CNA, which is what `Stream.over_bytes` is for.
          def GetAlbumArt
            verify_not_disposed!
            return nil unless self.HasArt

            bytes = CNA::Runtime::MediaSupport.bytes("cna_album_get_art_size", "cna_album_copy_art", @handle)
            bytes.empty? ? nil : CNA::Runtime::Stream.over_bytes(bytes, name: "#{self.Name} art")
          end

          def GetThumbnail
            verify_not_disposed!
            return nil unless self.HasArt

            bytes = CNA::Runtime::MediaSupport.bytes("cna_album_get_thumbnail_size",
                                                     "cna_album_copy_thumbnail", @handle)
            bytes.empty? ? nil : CNA::Runtime::Stream.over_bytes(bytes, name: "#{self.Name} thumbnail")
          end

          def Equals(other)
            return false unless other.is_a?(Album)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_album_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_album_get_hash_code", @handle)
          end

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_album_dispose"
          def media_destroy_route = "cna_album_destroy"

          def media_boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          def media_int32(symbol) = CNA::Runtime::MediaSupport.int32(symbol, @handle)
          def media_int64(symbol) = CNA::Runtime::MediaSupport.int64(symbol, @handle)
          def view(symbol) = CNA::Runtime::MediaSupport.handle_of(symbol, @handle)

          def optional(symbol)
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `Artist`: a media item. Its `Name`, disposal, equality and hash are the family's shape;
        # what is below is what this one adds.
        class Artist
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("artist", @handle)
          end

          def Albums
            verify_not_disposed!
            AlbumCollection.__send__(:from_native, view("cna_artist_get_albums"))
          end

          def Songs
            verify_not_disposed!
            SongCollection.__send__(:from_native, view("cna_artist_get_songs"))
          end

          def Equals(other)
            return false unless other.is_a?(Artist)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_artist_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_artist_get_hash_code", @handle)
          end

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_artist_dispose"
          def media_destroy_route = "cna_artist_destroy"

          def media_boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          def media_int32(symbol) = CNA::Runtime::MediaSupport.int32(symbol, @handle)
          def media_int64(symbol) = CNA::Runtime::MediaSupport.int64(symbol, @handle)
          def view(symbol) = CNA::Runtime::MediaSupport.handle_of(symbol, @handle)

          def optional(symbol)
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `Genre`: a media item. Its `Name`, disposal, equality and hash are the family's shape;
        # what is below is what this one adds.
        class Genre
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("genre", @handle)
          end

          def Albums
            verify_not_disposed!
            AlbumCollection.__send__(:from_native, view("cna_genre_get_albums"))
          end

          def Songs
            verify_not_disposed!
            SongCollection.__send__(:from_native, view("cna_genre_get_songs"))
          end

          def Equals(other)
            return false unless other.is_a?(Genre)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_genre_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_genre_get_hash_code", @handle)
          end

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_genre_dispose"
          def media_destroy_route = "cna_genre_destroy"

          def media_boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          def media_int32(symbol) = CNA::Runtime::MediaSupport.int32(symbol, @handle)
          def media_int64(symbol) = CNA::Runtime::MediaSupport.int64(symbol, @handle)
          def view(symbol) = CNA::Runtime::MediaSupport.handle_of(symbol, @handle)

          def optional(symbol)
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `Playlist`: a media item. Its `Name`, disposal, equality and hash are the family's shape;
        # what is below is what this one adds.
        class Playlist
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("playlist", @handle)
          end

          def Duration
            verify_not_disposed!
            CNA::Runtime::MediaSupport.seconds(media_int64("cna_playlist_get_duration"))
          end

          def Songs
            verify_not_disposed!
            SongCollection.__send__(:from_native, view("cna_playlist_get_songs"))
          end

          def Equals(other)
            return false unless other.is_a?(Playlist)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_playlist_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_playlist_get_hash_code", @handle)
          end

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_playlist_dispose"
          def media_destroy_route = "cna_playlist_destroy"

          def media_boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          def media_int32(symbol) = CNA::Runtime::MediaSupport.int32(symbol, @handle)
          def media_int64(symbol) = CNA::Runtime::MediaSupport.int64(symbol, @handle)
          def view(symbol) = CNA::Runtime::MediaSupport.handle_of(symbol, @handle)

          def optional(symbol)
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `Picture`: a media item. Its `Name`, disposal, equality and hash are the family's shape;
        # what is below is what this one adds.
        class Picture
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("picture", @handle)
          end

          def Album
            verify_not_disposed!
            optional("cna_picture_get_album") { |h| PictureAlbum.__send__(:from_native, h) }
          end

          def Width
            verify_not_disposed!
            media_int32("cna_picture_get_width")
          end

          def Height
            verify_not_disposed!
            media_int32("cna_picture_get_height")
          end

          # `get_Date` is a `System.DateTime`. CNA answers **100-nanosecond ticks from the Unix
          # epoch** rather than from the CLR's year 1, which its header says in as many words, so
          # the conversion is a division by ten million and nothing else. `System.DateTime` has no
          # entry in the BCL register and nothing else in the selected surface names it, so it
          # projects to Ruby's own `Time` — the same shape of decision `System.TimeSpan => Float`
          # already records, and the one Ruby type that is a point in time.
          def Date
            verify_not_disposed!
            Time.at(media_int64("cna_picture_get_date_unix_ticks") /
                    CNA::Runtime::MediaSupport::TICKS_PER_SECOND).utc
          end

          # `GetImage()` and `GetThumbnail()` each answer a `Stream` over the picture's bytes.
          def GetImage
            verify_not_disposed!
            CNA::Runtime::Stream.over_bytes(
              CNA::Runtime::MediaSupport.bytes("cna_picture_get_image_size",
                                               "cna_picture_copy_image", @handle),
              name: self.Name
            )
          end

          def GetThumbnail
            verify_not_disposed!
            CNA::Runtime::Stream.over_bytes(
              CNA::Runtime::MediaSupport.bytes("cna_picture_get_thumbnail_size",
                                               "cna_picture_copy_thumbnail", @handle),
              name: "#{self.Name} thumbnail"
            )
          end

          def Equals(other)
            return false unless other.is_a?(Picture)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_picture_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_picture_get_hash_code", @handle)
          end

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_picture_dispose"
          def media_destroy_route = "cna_picture_destroy"

          def media_boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          def media_int32(symbol) = CNA::Runtime::MediaSupport.int32(symbol, @handle)
          def media_int64(symbol) = CNA::Runtime::MediaSupport.int64(symbol, @handle)
          def view(symbol) = CNA::Runtime::MediaSupport.handle_of(symbol, @handle)

          def optional(symbol)
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `PictureAlbum`: a media item. Its `Name`, disposal, equality and hash are the family's shape;
        # what is below is what this one adds.
        class PictureAlbum
          include CNA::Runtime::MediaSupport::Disposable
          private_class_method :new

          def Name
            verify_not_disposed!
            CNA::Runtime::MediaSupport.name_of("picture_album", @handle)
          end

          def Albums
            verify_not_disposed!
            PictureAlbumCollection.__send__(:from_native, view("cna_picture_album_get_albums"))
          end

          def Pictures
            verify_not_disposed!
            PictureCollection.__send__(:from_native, view("cna_picture_album_get_pictures"))
          end

          def Parent
            verify_not_disposed!
            optional("cna_picture_album_get_parent") { |h| PictureAlbum.__send__(:from_native, h) }
          end

          def Equals(other)
            return false unless other.is_a?(PictureAlbum)
            return true if equal?(other)
            return false if @is_disposed || other.IsDisposed

            output = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_picture_album_equals", @handle, other.__send__(:native_handle), output)
            !output[0, 1].unpack1("C").zero?
          end

          def ==(other) = self.Equals(other)
          def eql?(other) = self.Equals(other)

          def GetHashCode
            verify_not_disposed!
            CNA::Runtime::MediaSupport.int32("cna_picture_album_get_hash_code", @handle)
          end

          def hash = self.GetHashCode

          def ToString = self.Name

          def to_s = self.ToString

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_picture_album_dispose"
          def media_destroy_route = "cna_picture_album_destroy"

          def media_boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, @handle)
          def media_int32(symbol) = CNA::Runtime::MediaSupport.int32(symbol, @handle)
          def media_int64(symbol) = CNA::Runtime::MediaSupport.int64(symbol, @handle)
          def view(symbol) = CNA::Runtime::MediaSupport.handle_of(symbol, @handle)

          def optional(symbol)
            handle = CNA::Runtime::MediaSupport.optional_handle(symbol, @handle)
            handle.nil? ? nil : yield(handle)
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `SongCollection`: a live view over a native list of `Song`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class SongCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_song_collection_dispose"
          def media_destroy_route = "cna_song_collection_destroy"
          def media_count_route = "cna_song_collection_get_count"

          def media_element(index)
            Song.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_song_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `AlbumCollection`: a live view over a native list of `Album`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class AlbumCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_album_collection_dispose"
          def media_destroy_route = "cna_album_collection_destroy"
          def media_count_route = "cna_album_collection_get_count"

          def media_element(index)
            Album.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_album_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `ArtistCollection`: a live view over a native list of `Artist`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class ArtistCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_artist_collection_dispose"
          def media_destroy_route = "cna_artist_collection_destroy"
          def media_count_route = "cna_artist_collection_get_count"

          def media_element(index)
            Artist.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_artist_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `GenreCollection`: a live view over a native list of `Genre`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class GenreCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_genre_collection_dispose"
          def media_destroy_route = "cna_genre_collection_destroy"
          def media_count_route = "cna_genre_collection_get_count"

          def media_element(index)
            Genre.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_genre_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `PlaylistCollection`: a live view over a native list of `Playlist`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class PlaylistCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_playlist_collection_dispose"
          def media_destroy_route = "cna_playlist_collection_destroy"
          def media_count_route = "cna_playlist_collection_get_count"

          def media_element(index)
            Playlist.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_playlist_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `PictureCollection`: a live view over a native list of `Picture`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class PictureCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_picture_collection_dispose"
          def media_destroy_route = "cna_picture_collection_destroy"
          def media_count_route = "cna_picture_collection_get_count"

          def media_element(index)
            Picture.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_picture_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `PictureAlbumCollection`: a live view over a native list of `PictureAlbum`. `Count`, `Item[int]` and
        # `GetEnumerator` are the whole of its own surface; disposal and the disposed guard are the
        # family's, in `CNA::Runtime::MediaSupport::Collection`.
        class PictureAlbumCollection
          include CNA::Runtime::MediaSupport::Collection
          private_class_method :new

          private

          def initialize_native(handle)
            @handle = handle
            @is_disposed = false
            self
          end

          def native_handle = @handle
          def media_dispose_route = "cna_picture_album_collection_dispose"
          def media_destroy_route = "cna_picture_album_collection_destroy"
          def media_count_route = "cna_picture_album_collection_get_count"

          def media_element(index)
            PictureAlbum.__send__(:from_native,
                              CNA::Runtime::MediaSupport.element_at("cna_picture_album_collection_get_at", @handle, index))
          end

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `MediaQueue`: the player's own list of songs, and the index it is playing.
        #
        # It is **not** a `MediaSupport::Collection`: the contract declares only `Count`,
        # `ActiveSongIndex`, `ActiveSong` and `Item[int]` — no `Dispose`, no `IsDisposed` and no
        # `GetEnumerator` — so it carries those four and nothing else.
        class MediaQueue
          private_class_method :new

          def Count = CNA::Runtime::MediaSupport.int32("cna_media_queue_get_count", @handle)

          # `get_ActiveSongIndex` answers **-1** when nothing is queued. The setter is public in the
          # pinned metadata — `set: true, setAccess: public` — so it is projected, and
          # `cna_media_queue_set_active_song_index` is what it reaches.
          def ActiveSongIndex = CNA::Runtime::MediaSupport.int32("cna_media_queue_get_active_song_index", @handle)

          def ActiveSongIndex=(value)
            CNA::Native.library.call("cna_media_queue_set_active_song_index", @handle,
                                     CNA::Runtime::Numeric.int32(value, "value"))
            value
          end

          def ActiveSong
            handle = CNA::Runtime::MediaSupport.optional_handle("cna_media_queue_get_active_song", @handle)
            handle.nil? ? nil : Song.__send__(:from_native, handle)
          end

          def [](index)
            raise ::TypeError, "index must be an Integer" unless index.is_a?(::Integer)

            Song.__send__(:from_native,
                          CNA::Runtime::MediaSupport.element_at("cna_media_queue_get_at", @handle, index))
          end

          private

          def initialize_native(handle)
            @handle = handle
            self
          end

          def native_handle = @handle

          class << self
            private

            def from_native(handle) = allocate.__send__(:initialize_native, handle)
          end
        end

        # `MediaPlayer` is an `abstract sealed` CLR class — a static one — and every member of it is
        # static. CNA's routes take the **Game handle** rather than a player handle, which is the
        # same shape: one player per process, reached through the game.
        #
        # `ActiveSongChanged` and `MediaStateChanged` are static events, projected as singleton
        # readers the way `Storage.StorageDevice.DeviceChanged` is. Their CNA subscriptions are
        # process-global and `_ext`, because XNA's own raisers are private.
        class MediaPlayer
          extend CNA::Runtime::EventOwner
          # `abstract sealed` in the CLR is a static class: it cannot be constructed and cannot be
          # derived from. Ruby has no such kind, so it is a class whose `new` is private — the same
          # projection every constructor-free XNA class here takes.
          private_class_method :new

          class << self
            def ActiveSongChanged = (@ActiveSongChanged ||= CNA::Runtime::Event.new)
            def MediaStateChanged = (@MediaStateChanged ||= CNA::Runtime::Event.new)

            # `Play(Song)`, `Play(SongCollection)` and `Play(SongCollection, int)`. Ruby cannot
            # dispatch on parameter type, so the three collapse into one method dispatching on the
            # argument's own type and arity — the rule every overload set here follows. A null
            # argument is `ArgumentNullException`, which is the IL's first statement in each.
            def Play(songOrCollection, index = nil)
              raise ::ArgumentError, "song" if songOrCollection.nil?

              case songOrCollection
              when Song
                raise ::ArgumentError, "index" unless index.nil?

                call("cna_media_player_play_song", songOrCollection.__send__(:native_handle))
              when SongCollection
                if index.nil?
                  call("cna_media_player_play_songs", songOrCollection.__send__(:native_handle))
                else
                  call("cna_media_player_play_songs_from", songOrCollection.__send__(:native_handle),
                       CNA::Runtime::Numeric.int32(index, "index"))
                end
              else
                raise ::TypeError, "Play takes a Song or a SongCollection"
              end
            end

            def Pause = call("cna_media_player_pause")
            def Resume = call("cna_media_player_resume")
            def Stop = call("cna_media_player_stop")
            def MoveNext = call("cna_media_player_move_next")
            def MovePrevious = call("cna_media_player_move_previous")

            # `GetVisualizationData(VisualizationData)` fills the caller's object and answers
            # nothing. The two arrays it fills are live views over the object's own storage, which
            # is what `VisualizationData` was projected for.
            def GetVisualizationData(visualizationData)
              raise ::ArgumentError, "visualizationData" if visualizationData.nil?
              unless visualizationData.instance_of?(VisualizationData)
                raise ::TypeError, "visualizationData must be a VisualizationData"
              end

              data = CNA::Native::Layouts::VisualizationData.new
              CNA::Native.library.call("cna_media_player_get_visualization_data", game_handle, data.pointer)
              visualizationData.__send__(:fill_from_native, data)
              nil
            end

            def Queue
              output = CNA::Native.library.pointer_for("Q", 0)
              CNA::Native.library.call("cna_media_player_get_queue", game_handle, output)
              MediaQueue.__send__(:from_native, output[0, 8].unpack1("Q"))
            end

            def State
              output = CNA::Native.library.pointer_for("L", 0)
              CNA::Native.library.call("cna_media_player_get_state", game_handle, output)
              MediaState.coerce(output[0, 4].unpack1("L"))
            end

            def PlayPosition
              CNA::Runtime::MediaSupport.seconds(
                CNA::Runtime::MediaSupport.int64("cna_media_player_get_play_position_ticks", game_handle)
              )
            end

            def GameHasControl = boolean("cna_media_player_get_game_has_control")
            def IsMuted = boolean("cna_media_player_get_is_muted")
            def IsRepeating = boolean("cna_media_player_get_is_repeating")
            def IsShuffled = boolean("cna_media_player_get_is_shuffled")
            def IsVisualizationEnabled = boolean("cna_media_player_get_is_visualization_enabled")

            # A setter cannot be an endless method definition in Ruby, which is the language
            # constraint every setter in this binding records.
            def IsMuted=(value)
              set_boolean("cna_media_player_set_is_muted", value, "IsMuted")
            end

            def IsRepeating=(value)
              set_boolean("cna_media_player_set_is_repeating", value, "IsRepeating")
            end

            def IsShuffled=(value)
              set_boolean("cna_media_player_set_is_shuffled", value, "IsShuffled")
            end

            def IsVisualizationEnabled=(value)
              set_boolean("cna_media_player_set_is_visualization_enabled", value, "IsVisualizationEnabled")
            end

            # `set_Volume` clamps rather than refusing: `MathHelper.Clamp(value, 0f, 1f)` is the
            # first statement, so 2.0 becomes 1.0 and -1.0 becomes 0.0 and neither raises.
            def Volume
              output = CNA::Native.library.pointer_for("e", 0.0)
              CNA::Native.library.call("cna_media_player_get_volume", game_handle, output)
              output[0, 4].unpack1("e")
            end

            def Volume=(value)
              number = CNA::Runtime::Numeric.f32(value)
              raise ::TypeError, "Volume must be a number" if number.nil?

              CNA::Native.library.call("cna_media_player_set_volume", game_handle,
                                       number.clamp(0.0, 1.0))
              value
            end

            private

            def game_handle
              CNA::Runtime::Context.__send__(:current_game, "MediaPlayer").__send__(:window_host_handle)
            end

            def call(symbol, *arguments)
              CNA::Native.library.call(symbol, game_handle, *arguments)
              nil
            end

            def boolean(symbol) = CNA::Runtime::MediaSupport.boolean(symbol, game_handle)

            def set_boolean(symbol, value, name)
              raise ::TypeError, "#{name} must be true or false" unless value == true || value == false

              CNA::Native.library.call(symbol, game_handle, value ? 1 : 0)
              value
            end
          end
        end

        # `MediaLibrary`: the producer for every other type in this namespace.
        #
        # Its two constructors are `MediaLibrary()` and `MediaLibrary(MediaSource)`; the second
        # refuses a null source with `ArgumentNullException`. Both reach CNA's own library, and
        # every collection property answers a **fresh live view** over the library's list, which is
        # what XNA's does.
        class MediaLibrary
          include CNA::Runtime::MediaSupport::Disposable
          public_class_method :new

          def initialize(mediaSource = nil)
            game = CNA::Runtime::Context.__send__(:current_game, "MediaLibrary")
            output = CNA::Native.library.pointer_for("Q", 0)
            @is_disposed = false
            if mediaSource.nil?
              CNA::Native.library.call("cna_media_library_create", game.__send__(:window_host_handle), output)
            else
              unless mediaSource.instance_of?(MediaSource)
                raise ::TypeError, "mediaSource must be a MediaSource"
              end

              CNA::Native.library.call("cna_media_library_create_from_source",
                                       game.__send__(:window_host_handle), 0, output)
            end
            @handle = output[0, 8].unpack1("Q")
            @MediaSource = mediaSource || MediaSource.GetAvailableMediaSources.first
          end

          attr_reader :MediaSource

          def Songs = collection("cna_media_library_get_songs") { |h| SongCollection.__send__(:from_native, h) }
          def Albums = collection("cna_media_library_get_albums") { |h| AlbumCollection.__send__(:from_native, h) }
          def Artists = collection("cna_media_library_get_artists") { |h| ArtistCollection.__send__(:from_native, h) }
          def Genres = collection("cna_media_library_get_genres") { |h| GenreCollection.__send__(:from_native, h) }
          def Playlists = collection("cna_media_library_get_playlists") { |h| PlaylistCollection.__send__(:from_native, h) }
          def Pictures = collection("cna_media_library_get_pictures") { |h| PictureCollection.__send__(:from_native, h) }
          def SavedPictures = collection("cna_media_library_get_saved_pictures") { |h| PictureCollection.__send__(:from_native, h) }

          # `get_RootPictureAlbum` answers the album every picture album descends from, or null when
          # the platform has none.
          def RootPictureAlbum
            verify_not_disposed!
            handle = CNA::Runtime::MediaSupport.optional_handle("cna_media_library_get_root_picture_album", @handle)
            handle.nil? ? nil : PictureAlbum.__send__(:from_native, handle)
          end

          # `GetPictureFromToken(string token)` answers the picture a token names, or null.
          def GetPictureFromToken(token)
            verify_not_disposed!
            raise ::ArgumentError, "token" if token.nil?

            view = CNA::Native::Layouts::StringView.new(String(token).b)
            value = CNA::Native.library.pointer_for("Q", 0)
            available = CNA::Native.library.pointer_for("C", 0)
            CNA::Native.library.call("cna_media_library_get_picture_from_token", @handle,
                                     view.read_u64(0), view.read_u64(8), value, available)
            return nil if available[0, 1].unpack1("C").zero?

            Picture.__send__(:from_native, value[0, 8].unpack1("Q"))
          end

          #     SavePicture(string name, byte[] source)
          #     SavePicture(string name, Stream source)
          #
          # Both refuse a null name or source. The `Stream` overload reads the stream whole and
          # hands the bytes to the same route, because CNA's stream form takes a **CNA** stream
          # handle and a `CNA::Runtime::Stream` is a managed buffer — reading it is the honest
          # bridge rather than inventing a handle.
          def SavePicture(name, source)
            verify_not_disposed!
            raise ::ArgumentError, "name" if name.nil?
            raise ::ArgumentError, "source" if source.nil?

            bytes = case source
                    when ::String then source.b
                    when CNA::Runtime::Stream then read_stream(source)
                    else raise ::TypeError, "source must be a byte String or a Stream"
                    end
            view = CNA::Native::Layouts::StringView.new(String(name).b)
            output = CNA::Native.library.pointer_for("Q", 0)
            CNA::Native.library.call("cna_media_library_save_picture", @handle,
                                     view.read_u64(0), view.read_u64(8),
                                     Fiddle::Pointer[bytes], bytes.bytesize, output)
            Picture.__send__(:from_native, output[0, 8].unpack1("Q"))
          end

          private

          def media_dispose_route = "cna_media_library_dispose"
          def media_destroy_route = "cna_media_library_destroy"

          def native_handle = @handle

          def collection(symbol)
            verify_not_disposed!
            yield(CNA::Runtime::MediaSupport.handle_of(symbol, @handle))
          end

          def read_stream(stream)
            buffer = +""
            chunk = "\0" * 65_536
            loop do
              read = stream.Read(chunk, 0, chunk.bytesize)
              break if read.zero?

              buffer << chunk[0, read]
            end
            buffer.b
          end
        end
      end
    end
  end
end
