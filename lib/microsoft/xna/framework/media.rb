# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # The pure managed XNA Media enum contracts, and the one Media type that is fully
      # constructible without a media stack. No MediaPlayer, MediaLibrary, Song, Video or playback
      # route is implemented or implied.
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
      end
    end
  end
end
